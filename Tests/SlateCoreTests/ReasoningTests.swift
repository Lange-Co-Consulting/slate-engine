import Testing
@testable import SlateCore

@Test func splitsThinkBlock() {
    let (th, ans) = Reasoning.split("<think>reasoning here</think>The answer.")
    #expect(th == "reasoning here")
    #expect(ans == "The answer.")
}

@Test func harmonyFinalChannelIsTheAnswer() {
    // gpt-oss: analysis (hidden CoT) then final (the answer).
    let text = "<|channel|>analysis<|message|>Let me think step by step.<|end|>"
        + "<|start|>assistant<|channel|>final<|message|>The answer is 42."
    let (th, ans) = Reasoning.split(text)
    #expect(ans == "The answer is 42.")
    #expect(th == "Let me think step by step.")
}

@Test func harmonyMidStreamHidesAnalysis() {
    // While the analysis channel is still streaming (no final yet) the answer
    // must be EMPTY — the chain-of-thought stays in the collapsible thoughts.
    let text = "<|channel|>analysis<|message|>weighing the options, still thinking"
    let (th, ans) = Reasoning.split(text)
    #expect(ans.isEmpty)
    #expect(th?.contains("weighing the options") == true)
}

@Test func splitsChannelMarkers() {
    // The gemma4-v2 leak: <|channel>thought … <channel|>answer
    let text = """
    <|channel>thought<|channel>thought
    Two questions. Keep it concise.
    <channel|>I'm trained on web text, books, and code.
    """
    let (th, ans) = Reasoning.split(text)
    #expect(ans == "I'm trained on web text, books, and code.")
    #expect(th?.contains("Two questions") == true)
    #expect(ans.contains("<|channel") == false)   // markers gone from the answer
    #expect(ans.contains("channel|>") == false)
}

@Test func stripRemovesReasoningKeepsAnswer() {
    let text = "<|channel>thought<|channel>thought\nthinking\n<channel|>Final answer."
    #expect(Reasoning.strip(text) == "Final answer.")
    #expect(Reasoning.strip("<think>a</think>b<think>c</think>d") == "bd")
}

@Test func doesNotStripRealMarkupFromAnswers() {
    // No control tokens → answer untouched (the </div>, <T> must survive).
    let html = "Here is code:\n```html\n<div class=\"x\"></div>\n```\nDone."
    let (th, ans) = Reasoning.split(html)
    #expect(th == nil)
    #expect(ans == html)
    #expect(ans.contains("</div>"))
}

@Test func keepsAnswerStartingWithFinallyWord() {
    // "Finally" must not be mistaken for a "final" channel label.
    let text = "<channel|>Finally, we ship it."
    #expect(Reasoning.split(text).answer == "Finally, we ship it.")
}

@Test func collectsAllThinkBlocks() {
    // Claude Code interleaves several <think> blocks with tool lines: ALL of them
    // go to thoughts, the tool activity + answer stay visible.
    let text = "<think>plan</think>\n`⚙ Edit foo`\n<think>more</think>\nDone."
    let (th, ans) = Reasoning.split(text)
    #expect(th == "plan\n\nmore")
    #expect(ans.contains("⚙ Edit foo") && ans.hasSuffix("Done."))
    #expect(!ans.contains("<think>"))
}

@Test func handlesUnclosedTrailingThink() {
    let (th, ans) = Reasoning.split("answer text <think>still thinking")
    #expect(th == "still thinking")
    #expect(ans == "answer text")
}
