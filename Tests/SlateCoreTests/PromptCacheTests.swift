import Testing
@testable import SlateCore

@Test func emptyNextFeedsNothing() {
    let p = PromptCache.plan(previous: [1, 2, 3], next: [])
    #expect(p.keep == 0)
    #expect(p.feed.isEmpty)
}

@Test func coldStartFeedsEverything() {
    let p = PromptCache.plan(previous: [], next: [1, 2, 3])
    #expect(p.keep == 0)
    #expect(p.feed == 0..<3)
}

@Test func extensionFeedsOnlyTheDelta() {
    // Turn 2 extends turn 1's transcript: only the new suffix is fed.
    let p = PromptCache.plan(previous: [1, 2, 3, 4], next: [1, 2, 3, 4, 9, 10])
    #expect(p.keep == 4)
    #expect(p.feed == 4..<6)
}

@Test func identicalPromptRefeedsLastToken() {
    // Regenerate: same prompt — keep all but one so decode yields fresh logits.
    let p = PromptCache.plan(previous: [5, 6, 7], next: [5, 6, 7])
    #expect(p.keep == 2)
    #expect(p.feed == 2..<3)
}

@Test func divergenceDropsTheTail() {
    // Edited history: shared system prompt survives, the rest is re-fed.
    let p = PromptCache.plan(previous: [1, 2, 99, 100], next: [1, 2, 3, 4, 5])
    #expect(p.keep == 2)
    #expect(p.feed == 2..<5)
}

@Test func generatedTokensCountTowardThePrefix() {
    // previous longer than next (e.g. long generation, next prompt truncates):
    // keep is capped by next.count - 1.
    let p = PromptCache.plan(previous: [1, 2, 3, 4, 5, 6], next: [1, 2, 3])
    #expect(p.keep == 2)
    #expect(p.feed == 2..<3)
}
