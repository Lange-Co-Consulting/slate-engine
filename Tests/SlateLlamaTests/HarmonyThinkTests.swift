import Testing
@testable import SlateLlama
import SlateCore

// These use the REAL gpt-oss stream shape (verified against the model's vocab:
// the control tokens <|channel|> <|message|> <|start|> <|end|> all render as
// literal text; only <|return|>/<|call|> are EOG and never reach us). The model
// is NOT prefilled into the analysis channel — it emits <|channel|>analysis…
// itself right after the <|start|>assistant generation prompt.

private func drive(_ pieces: [String]) -> String {
    let h = HarmonyThink(active: true)
    var full = ""
    for p in pieces { for out in h.feed(p) { full += out } }
    for out in h.finish() { full += out }
    return full
}

@Test func harmonyOneShotSplitsAnalysisAndFinal() {
    let raw = "<|channel|>analysis<|message|>We weigh the options.<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>The answer is 42."
    let (th, ans) = Reasoning.split(HarmonyThink.render(raw))
    #expect(ans == "The answer is 42.")
    #expect(th?.contains("weigh the options") == true)
    #expect(th?.contains("analysis") == false)   // label never leaks
    #expect(th?.contains("assistant") == false)
    #expect(th?.contains("final") == false)
}

@Test func harmonyMidAnalysisHasNoAnswerYet() {
    let raw = "<|channel|>analysis<|message|>still reasoning, no final channel yet"
    let (_, ans) = Reasoning.split(HarmonyThink.render(raw))
    #expect(ans.isEmpty)   // nothing shown as the answer during analysis
}

/// THE REGRESSION: streaming token-by-token, the analysis→final transition must
/// close <think> and reveal the final answer. The old whole-string-diff froze
/// here and dropped the entire answer.
@Test func harmonyStreamingRevealsFinalAnswer() {
    let pieces = [
        "<|channel|>", "analysis", "<|message|>",
        "The user asks", " a simple", " question.",
        "<|end|>", "<|start|>", "assistant", "<|channel|>", "final", "<|message|>",
        "No, I don't", " have access", " to your files.",
    ]
    let full = drive(pieces)
    let (th, ans) = Reasoning.split(full)
    #expect(ans == "No, I don't have access to your files.")
    #expect(th?.contains("simple question") == true)
    #expect(!full.contains("<|"))                 // all harmony markers stripped
    #expect(!ans.contains("analysis"))            // no label leak into the answer
    #expect(!ans.contains("assistant"))
}

/// Markers can also arrive glued to text within a single piece.
@Test func harmonyGluedMarkersStillSplit() {
    let pieces = [
        "<|channel|>analysis<|message|>Thinking hard.<|end|><|start|>assistant<|channel|>final<|message|>Done.",
    ]
    let (th, ans) = Reasoning.split(drive(pieces))
    #expect(ans == "Done.")
    #expect(th?.contains("Thinking hard") == true)
}

/// gpt-oss-20b sometimes emits a stray `commentary` channel before `final`; it's
/// hidden reasoning, not the answer.
@Test func harmonyCommentaryIsHidden() {
    let raw = "<|channel|>analysis<|message|>Reason.<|end|>"
            + "<|start|>assistant<|channel|>commentary<|message|>aside<|end|>"
            + "<|start|>assistant<|channel|>final<|message|>Answer."
    let (th, ans) = Reasoning.split(HarmonyThink.render(raw))
    #expect(ans == "Answer.")
    #expect(th?.contains("aside") == true)        // shown as reasoning, not answer
}

@Test func harmonyFeedIsAppendOnly() {
    // Deltas must never re-send already-emitted text (AppModel appends them).
    let h = HarmonyThink(active: true)
    var chunks: [String] = []
    for p in ["<|channel|>analysis<|message|>Hmm", "ing…", "<|end|><|start|>assistant<|channel|>final<|message|>", "Done."] {
        chunks.append(contentsOf: h.feed(p))
    }
    chunks.append(contentsOf: h.finish())
    let full = chunks.joined()
    let (th, ans) = Reasoning.split(full)
    #expect(ans == "Done.")
    #expect(th?.contains("Hmming") == true)
    #expect(!full.contains("<|"))
}

@Test func harmonyInactivePassesThrough() {
    let h = HarmonyThink(active: false)
    #expect(h.feed("plain text") == ["plain text"])
}

@Test func harmonyPlainTextFallback() {
    // Defensive: if a "harmony" model somehow streams no channel markers, don't
    // black-hole the output — surface it as the answer.
    let (_, ans) = Reasoning.split(drive(["Just plain text, no markers."]))
    #expect(ans == "Just plain text, no markers.")
}
