import Foundation

/// Separates a model's hidden reasoning from its actual answer, across the two
/// formats local models leak into raw text:
///   • DeepSeek-style `<think> … </think>`
///   • Harmony/channel markers, e.g. `<|channel>thought … <channel|>answer`
///     (some GGUFs render these control tokens as literal text).
/// Only pipe-bearing control tokens are stripped, so real markup like `</div>`
/// or `<T>` in a normal answer is left untouched.
public enum Reasoning {
    /// For display: the (collapsible) reasoning and the visible answer.
    public static func split(_ text: String) -> (thoughts: String?, answer: String) {
        if text.contains("<think>") {
            // Extract EVERY <think>…</think> block (Claude Code interleaves several
            // with tool calls), collect them into the collapsible thoughts, and
            // leave everything else - tool activity + the real answer - visible.
            var thoughts: [String] = []
            var answer = ""
            var rest = Substring(text)
            while let open = rest.range(of: "<think>") {
                answer += rest[..<open.lowerBound]
                let after = rest[open.upperBound...]
                if let close = after.range(of: "</think>") {
                    thoughts.append(trim(String(after[..<close.lowerBound])))
                    rest = after[close.upperBound...]
                } else {
                    thoughts.append(trim(String(after)))   // still streaming inside the last block
                    rest = after[after.endIndex...]
                    break
                }
            }
            answer += rest
            let t = trim(thoughts.filter { !$0.isEmpty }.joined(separator: "\n\n"))
            return (t.isEmpty ? nil : t, trim(answer))
        }
        if hasChannels(text) { return splitChannels(text) }
        return (nil, text)
    }

    /// For re-feeding into the next prompt: just the answer, with ALL reasoning
    /// blocks and stray control tokens removed.
    public static func strip(_ text: String) -> String {
        var t = text
        while let o = t.range(of: "<think>") {
            if let c = t.range(of: "</think>", range: o.upperBound..<t.endIndex) {
                t.removeSubrange(o.lowerBound..<c.upperBound)
            } else { t.removeSubrange(o.lowerBound..<t.endIndex); break }
        }
        if hasChannels(t) { t = splitChannels(t).answer }
        return stripControlTokens(t)
    }

    // MARK: - Helpers

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func hasChannels(_ s: String) -> Bool {
        s.range(of: #"<\|channel\|?>|<channel\|>"#, options: .regularExpression) != nil
            || s.contains("<|message|>")
    }

    /// Split on channel/message markers; the last non-empty segment is the answer,
    /// everything before it is reasoning.
    private static func splitChannels(_ text: String) -> (thoughts: String?, answer: String) {
        // gpt-oss / OpenAI-harmony first: route by channel NAME so the analysis
        // channel (which streams FIRST) never flashes as the answer.
        if let h = splitHarmony(text) { return h }
        let sentinel = "\u{1}"
        var s = text
        for pat in [#"<\|channel\|>"#, #"<\|channel>"#, #"<channel\|>"#, #"<\|message\|>"#] {
            s = s.replacingOccurrences(of: pat, with: sentinel, options: .regularExpression)
        }
        let pieces = s.components(separatedBy: sentinel).map(cleanPiece).filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return (nil, stripControlTokens(text)) }
        let answer = pieces.last ?? ""
        let thoughts = trim(pieces.dropLast().joined(separator: "\n"))
        return (thoughts.isEmpty ? nil : thoughts, answer)
    }

    /// gpt-oss / OpenAI-harmony: named channels `<|channel|>analysis<|message|>…`
    /// and `<|channel|>final<|message|>…`. The answer is ONLY the `final` channel;
    /// `analysis`/`commentary` are hidden reasoning. This is critical while
    /// STREAMING - the analysis channel arrives first, so a "last segment = answer"
    /// splitter would show the raw chain-of-thought as the answer until `final`
    /// appears. Returns nil for anything that isn't clearly this format, so the
    /// generic splitter (and its tests) are untouched.
    private static func splitHarmony(_ text: String) -> (thoughts: String?, answer: String)? {
        // Harmony always separates the channel name from its body with a message
        // marker. Without one, this isn't harmony (e.g. the gemma `<|channel>…`).
        guard text.range(of: #"<\|message\|?>"#, options: .regularExpression) != nil else { return nil }

        let delim = "\u{2}"
        var s = text
        for pat in [#"<\|channel\|>"#, #"<\|channel>"#] {
            s = s.replacingOccurrences(of: pat, with: delim, options: .regularExpression)
        }
        var analysis = "", final = "", sawNamed = false
        for seg in s.components(separatedBy: delim).dropFirst() {
            let name: String, body: Substring
            if let m = seg.range(of: #"<\|message\|?>"#, options: .regularExpression) {
                name = trim(String(seg[..<m.lowerBound])).lowercased()
                body = seg[m.upperBound...]
            } else {
                name = trim(seg).lowercased(); body = ""[...]   // name streamed, body not yet
            }
            // Cut the body at the next structural token (end/return/start/call).
            var content = String(body)
            for stop in ["<|end|>", "<|return|>", "<|start|>", "<|call|>"] {
                if let r = content.range(of: stop) { content = String(content[..<r.lowerBound]) }
            }
            content = stripControlTokens(content)
            if name.hasPrefix("final") {
                sawNamed = true; final += content
            } else if name.hasPrefix("analysis") || name.hasPrefix("commentary") || name.hasPrefix("thought") {
                sawNamed = true
                if !content.isEmpty { analysis += (analysis.isEmpty ? "" : "\n\n") + content }
            } else if !name.isEmpty {
                return nil   // an unrecognized channel name → not harmony we understand
            }
        }
        guard sawNamed else { return nil }
        let t = trim(analysis)
        return (t.isEmpty ? nil : t, trim(final))
    }

    /// Trim a segment and drop a leading channel-name label (analysis/final/…),
    /// but only when it stands alone (so "Finally," in a real answer is kept).
    private static func cleanPiece(_ p: String) -> String {
        var t = trim(p)
        // Drop a leading channel-name label only when it stands alone or is on its
        // own line (a real label) - never when it's a word in the answer like
        // "Final answer." (followed by a space) or "Finally" (followed by letters).
        for name in ["analysis", "commentary", "final", "thought"] where t.lowercased().hasPrefix(name) {
            let rest = t.dropFirst(name.count)
            if rest.isEmpty || rest.first!.isNewline { t = trim(String(rest)); break }
        }
        return stripControlTokens(t)
    }

    /// Remove only pipe-bearing control tokens - `<|name|>`, `<|name>`, `<name|>`  - 
    /// never plain markup like `</div>` or `<T>`.
    private static func stripControlTokens(_ s: String) -> String {
        trim(s.replacingOccurrences(of: #"<\|[A-Za-z_]+\|?>|<[A-Za-z_]+\|>"#,
                                    with: "", options: .regularExpression))
    }
}
