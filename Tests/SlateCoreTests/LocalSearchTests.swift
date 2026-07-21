import Testing
@testable import SlateCore

@Suite struct LocalSearchTests {
    @Test func matchesEveryTokenCaseAndDiacriticInsensitive() {
        #expect(LocalSearch.score(query: "uber blick", in: "Überblick über lokale Modelle") != nil)
        #expect(LocalSearch.score(query: "offline cloud", in: "Fully offline on this Mac") == nil)
    }

    @Test func earlierMatchesRankHigherAndSnippetCentersMatch() {
        let early = LocalSearch.score(query: "Slate", in: "Slate is local")!
        let late = LocalSearch.score(query: "Slate", in: String(repeating: "x", count: 150) + " Slate")!
        #expect(early > late)
        let snippet = LocalSearch.snippet(query: "needle", from: String(repeating: "a", count: 120) + " needle " + String(repeating: "b", count: 120), radius: 20)
        #expect(snippet.contains("needle"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
    }
}
