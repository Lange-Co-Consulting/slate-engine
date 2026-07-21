import Foundation
import Testing
@testable import SlateCore

@Test func searchURLCarriesQueryAndGGUFFilter() {
    let u = HFHub.searchURL(query: "qwen coder")!
    let c = URLComponents(url: u, resolvingAgainstBaseURL: false)!
    #expect(c.host == "huggingface.co")
    #expect(c.queryItems!.contains(URLQueryItem(name: "search", value: "qwen coder")))
    #expect(c.queryItems!.contains(URLQueryItem(name: "filter", value: "gguf")))
    #expect(c.queryItems!.contains(URLQueryItem(name: "sort", value: "downloads")))
}

@Test func resolveURLEncodesSegmentsButKeepsSlashes() {
    let u = HFHub.resolveURL(repo: "unsloth/Qwen3.5-9B-GGUF", path: "UD 2/model.gguf")!
    #expect(u.absoluteString == "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/UD%202/model.gguf")
    let t = HFHub.treeURL(repo: "unsloth/Qwen3.5-9B-GGUF")!
    #expect(t.absoluteString == "https://huggingface.co/api/models/unsloth/Qwen3.5-9B-GGUF/tree/main?recursive=true")
}

@Test func trendingURLSortsByTrendingScore() {
    let u = HFHub.trendingURL(limit: 50)!
    let c = URLComponents(url: u, resolvingAgainstBaseURL: false)!
    #expect(c.queryItems!.contains(URLQueryItem(name: "sort", value: "trendingScore")))
    #expect(c.queryItems!.contains(URLQueryItem(name: "filter", value: "gguf")))
    #expect(c.queryItems!.contains(URLQueryItem(name: "limit", value: "50")))
}

@Test func repoDecodesTrendingScore() {
    let repos = HFHub.parseRepos(Data(#"[{"id":"a/b","trendingScore":699,"downloads":5}]"#.utf8))
    #expect(repos.first?.trendingScore == 699)
}

@Test func fractionalTrendingScoreDoesNotDropTheList() {
    // The Hub sends non-integer trendingScore for lower-ranked models. A strict
    // decode would fail the whole array; the lenient parser must keep every repo
    // (coercing the fractional score) so the trending list is not silently empty.
    let repos = HFHub.parseRepos(Data("""
    [{"id":"top/a","trendingScore":497,"downloads":74007},
     {"id":"mid/b","trendingScore":8.333,"downloads":12},
     {"id":"low/c","trendingScore":0.5,"likes":3}]
    """.utf8))
    #expect(repos.count == 3)
    #expect(repos[0].trendingScore == 497)
    #expect(repos[1].trendingScore == 8)
    #expect(repos[2].trendingScore == 0)
    #expect(repos[2].likes == 3)
}

@Test func parsesSearchAndTreePayloads() {
    let repos = HFHub.parseRepos(Data("""
    [{"id":"unsloth/Qwen3.5-9B-GGUF","downloads":12345,"likes":67,"private":false},
     {"id":"bartowski/EuroLLM-9B-Instruct-GGUF"}]
    """.utf8))
    #expect(repos.count == 2)
    #expect(repos[0].downloads == 12345)
    #expect(repos[1].likes == nil)

    let tree = HFHub.parseTree(Data("""
    [{"type":"file","path":"a-Q4_K_M.gguf","size":100},
     {"type":"file","path":"sub/b-Q8_0.gguf","size":300},
     {"type":"file","path":"mmproj-f16.gguf","size":50},
     {"type":"file","path":"README.md","size":1},
     {"type":"directory","path":"sub"}]
    """.utf8))
    #expect(tree.count == 5)
    let files = HFHub.ggufFiles(repo: "x/y", tree: tree)
    #expect(files.map(\.fileName) == ["a-Q4_K_M.gguf", "b-Q8_0.gguf", "mmproj-f16.gguf"])
    #expect(files[0].bytes == 100)               // smallest chat model first
    #expect(files[2].isProjector)                 // projector sorted last
    #expect(files[1].downloadURL!.absoluteString == "https://huggingface.co/x/y/resolve/main/sub/b-Q8_0.gguf")
}
