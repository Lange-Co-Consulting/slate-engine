import Testing
import Foundation
@testable import SlateCore

@Test func webSearchConfigConfiguredRules() {
    // Hosted providers need a key.
    #expect(WebSearchConfig(provider: .brave, apiKey: nil, searxngURL: nil).isConfigured == false)
    #expect(WebSearchConfig(provider: .brave, apiKey: "", searxngURL: nil).isConfigured == false)
    #expect(WebSearchConfig(provider: .brave, apiKey: "k", searxngURL: nil).isConfigured == true)
    #expect(WebSearchConfig(provider: .tavily, apiKey: "k", searxngURL: nil).isConfigured == true)
    // SearXNG needs a valid http(s) base URL, no key.
    #expect(WebSearchConfig(provider: .searxng, apiKey: nil, searxngURL: nil).isConfigured == false)
    #expect(WebSearchConfig(provider: .searxng, apiKey: nil, searxngURL: "not a url").isConfigured == false)
    #expect(WebSearchConfig(provider: .searxng, apiKey: nil, searxngURL: "https://searx.example").isConfigured == true)
}

@Test func webSearchProviderMetadata() {
    #expect(WebSearchProvider.brave.needsKey == true)
    #expect(WebSearchProvider.tavily.needsKey == true)
    #expect(WebSearchProvider.searxng.needsKey == false)
    #expect(WebSearchProvider.allCases.count == 3)
}

@Test func webSearchToolsExposeSearchAndFetch() {
    let tools = WebSearch.tools(config: WebSearchConfig(provider: .brave, apiKey: "k", searxngURL: nil),
                                session: WebSearch.makeSession())
    #expect(tools.count == 2)
    #expect(tools.map(\.spec.name).sorted() == ["fetch_url", "web_search"])
}

/// Without credentials the tool must fail SAFELY — a clear string, never a throw/crash,
/// and never a network call (isConfigured is false so it returns before touching the net).
@Test func webSearchFailsSafelyWithoutCredentials() async throws {
    let tools = WebSearch.tools(config: WebSearchConfig(provider: .brave, apiKey: nil, searxngURL: nil),
                                session: WebSearch.makeSession())
    let search = try #require(tools.first { $0.spec.name == "web_search" })
    let output = try await search.run(["query": "anything"])
    #expect(output.contains("failed") || output.contains("configured"))
}

@Test func webSearchToolRejectsEmptyQuery() async throws {
    let tools = WebSearch.tools(config: WebSearchConfig(provider: .brave, apiKey: "k", searxngURL: nil),
                                session: WebSearch.makeSession())
    let search = try #require(tools.first { $0.spec.name == "web_search" })
    let output = try await search.run(["query": "   "])
    #expect(output.lowercased().contains("required"))
}
