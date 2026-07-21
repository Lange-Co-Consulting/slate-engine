import Testing
@testable import SlateLlama
import SlateCore

// Adversarial stress tests for HarmonyThink's streaming parser.
//
// These compare the streamed concatenation (feed…/finish) directly against the
// one-shot HarmonyThink.render(rawSoFar) for the SAME raw — that IS the
// append-only invariant: emitting deltas token-by-token must reconstruct the
// exact same display as parsing the whole string at once.
//
// Named "harmony…" so `swift test --filter harmony` includes them.

/// Drive a piece sequence through a fresh HarmonyThink and concatenate every
/// delta from feed() plus finish() — i.e. what the UI would accumulate.
private func harmonyDrive(_ pieces: [String]) -> String {
    let h = HarmonyThink(active: true)
    var full = ""
    for p in pieces { for out in h.feed(p) { full += out } }
    for out in h.finish() { full += out }
    return full
}

/// Split `raw` into pieces at the given character indices (0/…/end filtered out).
private func harmonySplit(_ raw: String, at cuts: [Int]) -> [String] {
    let chars = Array(raw)
    var pieces: [String] = []
    var prev = 0
    for c in cuts.sorted() where c > prev && c < chars.count {
        pieces.append(String(chars[prev..<c])); prev = c
    }
    pieces.append(String(chars[prev...]))
    return pieces
}

/// The "visible answer": everything after the </think> close tag (or the whole
/// output when there is no think block), trimmed of the block separator
/// whitespace the way the display layer (Reasoning.split) does.
private func harmonyVisibleAnswer(_ full: String) -> String {
    let tail = full.range(of: "</think>").map { String(full[$0.upperBound...]) } ?? full
    return tail.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Invariant #1: append-only == one-shot render, over every split point

/// Fixed realistic raw (analysis → final), cut at EVERY single character index.
/// Every split must rebuild exactly HarmonyThink.render(raw).
@Test func harmonyAdvAppendOnlyEverySingleSplit() {
    let raw = "<|channel|>analysis<|message|>reasoning here<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>The final answer."
    let oneShot = HarmonyThink.render(raw)
    let n = Array(raw).count
    var failures: [Int] = []
    var firstDiff = ""
    for cut in 1..<n {
        let got = harmonyDrive(harmonySplit(raw, at: [cut]))
        if got != oneShot {
            failures.append(cut)
            if firstDiff.isEmpty { firstDiff = "cut=\(cut) got=\(got.debugDescription) want=\(oneShot.debugDescription)" }
        }
    }
    #expect(failures.isEmpty, "append-only broke at split indices \(failures). First: \(firstDiff)")
}

/// Many pseudo-random multi-cut splits of a fixed raw (deterministic xorshift).
@Test func harmonyAdvAppendOnlyRandomMultiCut() {
    let raw = "<|channel|>analysis<|message|>weighing the options carefully<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>The answer is 42, definitely."
    let oneShot = HarmonyThink.render(raw)
    let n = Array(raw).count
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
    var failures = 0
    var firstBad = ""
    for _ in 0..<400 {
        let k = Int(rnd() % 4) + 1
        var cuts = Set<Int>()
        for _ in 0..<k { cuts.insert(Int(rnd() % UInt64(n))) }
        let got = harmonyDrive(harmonySplit(raw, at: Array(cuts)))
        if got != oneShot {
            failures += 1
            if firstBad.isEmpty { firstBad = "cuts=\(cuts.sorted()) got=\(got.debugDescription)" }
        }
    }
    #expect(failures == 0, "random splits diverged \(failures)x. First: \(firstBad)")
}

// MARK: - Invariant #2/#3: partial control markers must never leak

/// A stop marker (<|end|>) split right before its closing '>' — pieces
/// "…<|end|" then ">". The holdback must swallow the fragment; nothing that
/// looks like a marker may reach the visible answer.
@Test func harmonyAdvPartialEndMarkerNoLeakIntoAnswer() {
    let pieces = ["<|channel|>final<|message|>Hello world", "<|end|", ">"]
    let full = harmonyDrive(pieces)
    let ans = harmonyVisibleAnswer(full)
    #expect(!ans.contains("<|"), "marker fragment leaked into answer: \(ans.debugDescription)")
    #expect(ans == "Hello world", "answer corrupted by split marker: \(ans.debugDescription)")
}

/// Same split, but the marker terminates the ANALYSIS body. The fragment must
/// not appear inside the think block, and the whole display must match render.
@Test func harmonyAdvPartialEndMarkerNoLeakIntoThink() {
    let pieces = ["<|channel|>analysis<|message|>reasoning", "<|end|", ">",
                  "<|start|>assistant<|channel|>final<|message|>", "Answer."]
    let full = harmonyDrive(pieces)
    let raw = "<|channel|>analysis<|message|>reasoning<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>Answer."
    #expect(!full.contains("<|"), "marker fragment leaked into think: \(full.debugDescription)")
    #expect(full == HarmonyThink.render(raw), "display diverged: \(full.debugDescription)")
}

/// The exact split shape called out in invariant #3: the `final<|message|>`
/// marker fragmented as "…final", "<|mess", "age|>", "Answer".
@Test func harmonyAdvFinalMessageMarkerSplitReassembles() {
    let pieces = ["<|channel|>analysis<|message|>think<|end|><|start|>assistant<|channel|>",
                  "final", "<|mess", "age|>", "The answer."]
    let full = harmonyDrive(pieces)
    let raw = "<|channel|>analysis<|message|>think<|end|><|start|>assistant<|channel|>final<|message|>The answer."
    #expect(harmonyVisibleAnswer(full) == "The answer.")
    #expect(!full.contains("<|"))
    #expect(full == HarmonyThink.render(raw))
}

// MARK: - Invariant #4: literal angle brackets / pseudo-markers in the answer

/// `a < b`, `<div>`, and a non-control `<|x|>` are legitimate content and must
/// survive every split unchanged (none of them are harmony stop markers).
@Test func harmonyAdvLiteralAngleBracketsPreserved() {
    let raw = "<|channel|>final<|message|>if a < b and x<y use <div> or <|x|> ok"
    let oneShot = HarmonyThink.render(raw)
    #expect(harmonyVisibleAnswer(oneShot).contains("a < b"))
    #expect(harmonyVisibleAnswer(oneShot).contains("<div>"))
    let n = Array(raw).count
    var bad: [Int] = []
    for cut in 1..<n where harmonyDrive(harmonySplit(raw, at: [cut])) != oneShot { bad.append(cut) }
    #expect(bad.isEmpty, "angle-bracket content diverged at splits \(bad)")
}

/// An `<|end|>` sequence inside the final body IS the structural end-of-message
/// marker per the harmony spec — the tokenizer never produces it as content, so
/// treating it as content would be wrong. Correct behavior: the body ends
/// cleanly before it and no marker fragment ever leaks.
@Test func harmonyAdvEndTokenInFinalEndsBodyCleanly() {
    let raw = "<|channel|>final<|message|>The token <|end|> means stop."
    let ans = harmonyVisibleAnswer(HarmonyThink.render(raw))
    #expect(ans == "The token")
    #expect(!ans.contains("<|"))
}

// MARK: - Invariant #5: reasoning-effort variations

/// Low effort: raw begins directly with the final channel, no analysis at all.
/// No think block, answer verbatim, stable across every split.
@Test func harmonyAdvFinalOnlyNoAnalysis() {
    let raw = "<|channel|>final<|message|>Direct answer, no analysis at all."
    let oneShot = HarmonyThink.render(raw)
    #expect(!oneShot.contains("<think>"))
    #expect(oneShot == "Direct answer, no analysis at all.")
    let n = Array(raw).count
    var bad: [Int] = []
    for cut in 1..<n where harmonyDrive(harmonySplit(raw, at: [cut])) != oneShot { bad.append(cut) }
    #expect(bad.isEmpty, "final-only diverged at splits \(bad)")
}

/// A `commentary to=functions.foo` tool preamble before final. The tool label
/// and routing must not leak into the visible answer.
@Test func harmonyAdvCommentaryToolPreambleBeforeFinal() {
    let raw = "<|channel|>analysis<|message|>Think.<|end|>"
            + "<|start|>assistant<|channel|>commentary to=functions.lookup<|message|>{\"q\":1}<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>Here is the answer."
    let full = harmonyDrive([raw])
    let ans = harmonyVisibleAnswer(full)
    #expect(ans == "Here is the answer.")
    #expect(!ans.contains("functions"))
    #expect(!ans.contains("commentary"))
    #expect(!ans.contains("to="))
    #expect(!ans.contains("<|"))
    #expect(full == HarmonyThink.render(raw))
}

// MARK: - Invariant #6: empty / whitespace bodies

/// Empty analysis body and empty final body must stream identically to render.
@Test func harmonyAdvEmptyBodiesConsistent() {
    let raws = [
        "<|channel|>analysis<|message|><|end|><|start|>assistant<|channel|>final<|message|>Answer.",
        "<|channel|>analysis<|message|>Reason.<|end|><|start|>assistant<|channel|>final<|message|>",
    ]
    for raw in raws {
        #expect(harmonyDrive([raw]) == HarmonyThink.render(raw),
                "empty-body mismatch: \(raw.debugDescription)")
    }
}

/// Whitespace-only / surrounded analysis: streaming forwards the body raw while
/// render trims it — do they still agree?
@Test func harmonyAdvAnalysisSurroundingWhitespaceMatchesRender() {
    let raw = "<|channel|>analysis<|message|>   spaced reasoning   <|end|>"
            + "<|start|>assistant<|channel|>final<|message|>Answer."
    #expect(harmonyDrive([raw]) == HarmonyThink.render(raw),
            "streamed think whitespace diverged from render: \(harmonyDrive([raw]).debugDescription)")
}
