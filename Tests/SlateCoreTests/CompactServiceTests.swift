import Testing
@testable import SlateCore

@Test func compactSplitsOlderHalfKeepingSystemAndRecent() {
    let msgs = (0..<10).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, content: "m\($0)") }
    let plan = CompactService.plan(messages: [ChatMessage(role: .system, content: "sys")] + msgs, keepRecent: 4)
    #expect(plan.toSummarize.count == 6)      // older half (10 - 4 recent)
    #expect(plan.keep.map(\.content) == ["m6","m7","m8","m9"])
    #expect(plan.systemCount == 1)
}

@Test func compactNoOpWhenShort() {
    let msgs = [ChatMessage(role: .user, content: "a"), ChatMessage(role: .assistant, content: "b")]
    #expect(CompactService.plan(messages: msgs, keepRecent: 4).toSummarize.isEmpty)
}

@Test func compactSummaryPromptIncludesTranscript() {
    let p = CompactService.summaryPrompt(for: [ChatMessage(role: .user, content: "hello world")])
    #expect(p.contains("hello world"))
    #expect(p.lowercased().contains("summary"))
}
