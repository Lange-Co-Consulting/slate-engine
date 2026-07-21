import Testing
import Foundation
@testable import SlateCore

@Test func trimKeepsSystemAndNewestDropsOldest() {
    let msgs = [
        ChatMessage(role: .system, content: String(repeating: "s", count: 40)),   // ~18 tok
        ChatMessage(role: .user, content: String(repeating: "a", count: 400)),    // ~108 tok  (oldest)
        ChatMessage(role: .assistant, content: String(repeating: "b", count: 400)),
        ChatMessage(role: .user, content: String(repeating: "c", count: 40)),     // ~18 tok  (newest)
    ]
    let (kept, trimmed) = ContextBudget.trim(msgs, approxTokenBudget: 60)
    #expect(kept.first?.role == .system)                 // system always kept
    #expect(kept.last?.content.first == "c")             // newest kept
    #expect(!kept.contains { $0.content.first == "a" })  // oldest dropped
    #expect(trimmed >= 1)
}

@Test func trimReturnsInputWhenUnderBudget() {
    let msgs = [ChatMessage(role: .user, content: "hi"), ChatMessage(role: .assistant, content: "yo")]
    let (kept, trimmed) = ContextBudget.trim(msgs, approxTokenBudget: 10_000)
    #expect(kept == msgs)
    #expect(trimmed == 0)
}

@Test func trimAlwaysKeepsAtLeastNewestEvenIfOversized() {
    let msgs = [ChatMessage(role: .user, content: String(repeating: "x", count: 8000))]
    let (kept, trimmed) = ContextBudget.trim(msgs, approxTokenBudget: 10)
    #expect(kept.count == 1)      // never returns empty
    #expect(trimmed == 0)
}

@Test func trimNoBudgetIsNoOp() {
    let msgs = [ChatMessage(role: .user, content: "a"), ChatMessage(role: .user, content: "b")]
    #expect(ContextBudget.trim(msgs, approxTokenBudget: 0).kept == msgs)
}
