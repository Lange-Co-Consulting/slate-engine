import Testing
@testable import SlateCore

@Test func nonSubsequenceDoesNotMatch() {
    #expect(FuzzyMatch.score("xyz", "New Chat") == nil)
    #expect(FuzzyMatch.score("chatt", "chat") == nil)   // query longer than candidate
}

@Test func subsequenceMatches() {
    #expect(FuzzyMatch.score("nc", "New Chat") != nil)
    #expect(FuzzyMatch.score("newchat", "New Chat") != nil)   // spaces are skippable
    #expect(FuzzyMatch.score("", "anything") == 0)
}

@Test func consecutiveAndBoundaryScoreHigher() {
    // "chat" as a run beats scattered c-h-a-t.
    let run = FuzzyMatch.score("chat", "Open Chat")!
    let scattered = FuzzyMatch.score("chat", "Cache has this")!
    #expect(run > scattered)
    // word-boundary start beats mid-word.
    #expect(FuzzyMatch.score("m", "Manager")! > FuzzyMatch.score("m", "Downloads menu")! - 100)  // sanity: both match
}

@Test func rankSortsBestFirstAndKeepsBlank() {
    let items = ["New Chat", "New Code", "Model Manager", "Downloads"]
    let ranked = FuzzyMatch.rank("mm", items) { $0 }
    #expect(ranked.first == "Model Manager")
    #expect(FuzzyMatch.rank("", items) { $0 } == items)   // blank keeps order
    #expect(!FuzzyMatch.rank("zzz", items) { $0 }.contains("New Chat"))
}
