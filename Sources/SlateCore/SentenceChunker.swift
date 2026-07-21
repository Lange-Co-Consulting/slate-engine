import Foundation

/// Slices a streaming LLM answer into speakable chunks for sentence-by-sentence
/// TTS: the first sentence can be spoken while the rest still generates.
/// Skips <think>…</think> reasoning and fenced code (voice summarizes around
/// code; the text transcript is the place to read it), strips inline markdown,
/// and holds chunks until they're long enough to sound natural.
public struct SentenceChunker {
    private var buffer = ""
    private var inThink = false
    private var inFence = false
    /// Chunks shorter than this wait for the next sentence (avoids robotic
    /// staccato from "Ja." / "Ok." fragments).
    private let minChunk = 25

    public init() {}

    /// Feed the next raw token(s); returns any chunks that became complete.
    public mutating func feed(_ piece: String) -> [String] {
        buffer += piece
        var out: [String] = []
        var progressed = true
        while progressed {
            progressed = false
            if inThink {
                if let r = buffer.range(of: "</think>") {
                    buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                    inThink = false
                    progressed = true
                } else if buffer.count > 8 {
                    // Keep only a tail that could still hold a partial "</think>".
                    buffer.removeFirst(buffer.count - 8)
                }
            } else if inFence {
                if let r = buffer.range(of: "```") {
                    buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                    inFence = false
                    progressed = true
                } else if buffer.count > 3 {
                    buffer.removeFirst(buffer.count - 3)
                }
            } else {
                let think = buffer.range(of: "<think>")
                let fence = buffer.range(of: "```")
                // Whichever marker comes first bounds the speakable region.
                let cut = [think, fence].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
                if let cut {
                    let speakable = String(buffer[buffer.startIndex..<cut.lowerBound])
                    out += emit(from: speakable, flushAll: true)
                    let isThink = cut == think
                    buffer.removeSubrange(buffer.startIndex..<cut.upperBound)
                    if isThink { inThink = true } else { inFence = true }
                    progressed = true
                } else {
                    let (chunks, rest) = splitSentences(buffer)
                    if !chunks.isEmpty {
                        out += chunks
                        buffer = rest
                        progressed = true
                    }
                }
            }
        }
        return out
    }

    /// Flush whatever remains (stream ended).
    public mutating func finish() -> [String] {
        defer { buffer = ""; inThink = false; inFence = false }
        guard !inThink, !inFence else { return [] }
        return emit(from: buffer, flushAll: true)
    }

    // MARK: internals

    /// Split completed sentences off the front of `text`; keep the tail.
    private func splitSentences(_ text: String) -> (chunks: [String], rest: String) {
        var chunks: [String] = []
        var pending = ""
        var rest = text
        while true {
            // Paragraph break flushes regardless of punctuation; sentence enders
            // need a following space/newline so "3.14" mid-number doesn't split.
            let para = rest.range(of: "\n\n")
            let ender = rest.range(of: #"[.!?…]["')\]]?[ \n]"#, options: .regularExpression)
            if let para, ender == nil || para.lowerBound < ender!.lowerBound {
                let head = String(rest[rest.startIndex..<para.lowerBound])
                rest.removeSubrange(rest.startIndex..<para.upperBound)
                let joined = pending + head
                pending = ""
                if let c = clean(joined) { chunks.append(c) }
                continue
            }
            guard let ender else { break }
            let head = String(rest[rest.startIndex..<ender.upperBound])
            rest.removeSubrange(rest.startIndex..<ender.upperBound)
            let candidate = pending + head
            if candidate.trimmingCharacters(in: .whitespacesAndNewlines).count >= minChunk {
                if let c = clean(candidate) { chunks.append(c) }
                pending = ""
            } else {
                pending = candidate   // too short to speak alone - merge forward
            }
        }
        return (chunks, pending + rest)
    }

    private func emit(from text: String, flushAll: Bool) -> [String] {
        let (chunks, rest) = splitSentences(text)
        var out = chunks
        if flushAll, let c = clean(rest) { out.append(c) }
        return out
    }

    /// Strip inline markdown + collapse whitespace; nil when nothing speakable.
    private func clean(_ raw: String) -> String? {
        var s = raw
        for junk in ["**", "__", "*", "`", "#"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
