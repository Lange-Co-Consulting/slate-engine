import Foundation
import Testing
@testable import SlateCore

@Suite("Reasoning: templates that pre-fill the opening <think>")
struct ReasoningOrphanTests {
    /// Qwen3 / DeepSeek-R1 templates put "<think>" in the PROMPT, so the model's own
    /// output starts mid-thought and only emits the closing tag.
    private let leaked = """
    The user wants a rate limiter. Let me weigh token bucket vs sliding window.
    </think>
    Use a token bucket per API key.
    """

    @Test("The chain of thought is not shown as the answer")
    func splitsOrphanedClose() {
        let (thoughts, answer) = Reasoning.split(leaked)
        #expect(answer == "Use a token bucket per API key.")
        #expect(thoughts?.contains("token bucket vs sliding window") == true)
        #expect(answer.contains("Let me weigh") == false)
    }

    @Test("Re-feeding the turn keeps only the answer")
    func stripsOrphanedClose() {
        let out = Reasoning.strip(leaked)
        #expect(out.contains("Let me weigh") == false)
        #expect(out.contains("Use a token bucket per API key.") == true)
    }

    @Test("Normal <think>…</think> output still works")
    func regularBlockUnchanged() {
        let (t, a) = Reasoning.split("<think>hidden</think>visible")
        #expect(t == "hidden")
        #expect(a == "visible")
    }

    @Test("Plain answers are untouched")
    func plainUntouched() {
        let (t, a) = Reasoning.split("Just an answer.")
        #expect(t == nil)
        #expect(a == "Just an answer.")
    }

    @Test("A stray </div> is not treated as reasoning")
    func markupUntouched() {
        let (t, a) = Reasoning.split("Wrap it in </div> like so.")
        #expect(t == nil)
        #expect(a == "Wrap it in </div> like so.")
    }
}
