import Foundation

/// On-demand web search for local models: a bring-your-own-provider tool that turns a
/// query into ranked results and fetches page text. Public engine infra so both the
/// app's local chat runs and slate-pro's automation runs can register it. The key lives
/// in the Keychain; the caller only builds these tools when the user enabled search, a
/// provider is configured, and Silent Mode is off — so network stays fully opt-in.
public enum WebSearchProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case brave, tavily, searxng
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .brave: return "Brave Search"
        case .tavily: return "Tavily"
        case .searxng: return "SearXNG (self-hosted)"
        }
    }
    /// SearXNG is self-hosted and can run keyless; the hosted APIs require a key.
    public var needsKey: Bool { self != .searxng }
    /// Where to get a key / set up the provider (shown in Settings).
    public var setupURL: String {
        switch self {
        case .brave: return "https://brave.com/search/api/"
        case .tavily: return "https://tavily.com/"
        case .searxng: return "https://docs.searxng.org/"
        }
    }
}

public struct WebSearchResult: Sendable, Equatable {
    public let title: String
    public let url: String
    public let snippet: String
    public init(title: String, url: String, snippet: String) {
        self.title = title; self.url = url; self.snippet = snippet
    }
}

public struct WebSearchConfig: Sendable, Equatable {
    public var provider: WebSearchProvider
    public var apiKey: String?
    /// Base URL for a self-hosted SearXNG instance (e.g. https://searx.example.org).
    public var searxngURL: String?
    public init(provider: WebSearchProvider, apiKey: String?, searxngURL: String?) {
        self.provider = provider; self.apiKey = apiKey; self.searxngURL = searxngURL
    }
    /// Whether the config is usable (has a key where required, and a valid SearXNG URL).
    public var isConfigured: Bool {
        switch provider {
        case .searxng:
            guard let s = searxngURL, let u = URL(string: s), u.scheme?.hasPrefix("http") == true else { return false }
            return true
        default:
            return (apiKey?.isEmpty == false)
        }
    }
}

public enum WebSearchError: LocalizedError {
    case notConfigured
    case http(Int)
    case badResponse
    case badURL
    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Web search has no provider or API key configured (Settings → Web Search)."
        case .http(let c): return "The search provider returned HTTP \(c)."
        case .badResponse: return "The search provider returned an unexpected response."
        case .badURL: return "Invalid URL."
        }
    }
}

public enum WebSearch {
    /// A dedicated session with modest timeouts. Network is only reached when the caller
    /// has already decided search is permitted (enabled + configured + not Silent Mode).
    public static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        return URLSession(configuration: cfg)
    }

    public static func search(_ query: String, config: WebSearchConfig, limit: Int = 8,
                              session: URLSession) async throws -> [WebSearchResult] {
        guard config.isConfigured else { throw WebSearchError.notConfigured }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        switch config.provider {
        case .brave:   return try await brave(q, key: config.apiKey ?? "", limit: limit, session: session)
        case .tavily:  return try await tavily(q, key: config.apiKey ?? "", limit: limit, session: session)
        case .searxng: return try await searxng(q, base: config.searxngURL ?? "", limit: limit, session: session)
        }
    }

    // MARK: providers

    private static func brave(_ q: String, key: String, limit: Int, session: URLSession) async throws -> [WebSearchResult] {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(enc)&count=\(limit)") else { throw WebSearchError.badURL }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await get(req, session: session)
        struct R: Decodable { struct Web: Decodable { struct Item: Decodable { let title: String?; let url: String?; let description: String? }; let results: [Item]? }; let web: Web? }
        let decoded = try JSONDecoder().decode(R.self, from: data)
        return (decoded.web?.results ?? []).prefix(limit).map {
            WebSearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: clean($0.description ?? ""))
        }
    }

    private static func tavily(_ q: String, key: String, limit: Int, session: URLSession) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else { throw WebSearchError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": key, "query": q, "max_results": limit, "search_depth": "basic",
        ])
        let data = try await get(req, session: session)
        struct R: Decodable { struct Item: Decodable { let title: String?; let url: String?; let content: String? }; let results: [Item]? }
        let decoded = try JSONDecoder().decode(R.self, from: data)
        return (decoded.results ?? []).prefix(limit).map {
            WebSearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: clean($0.content ?? ""))
        }
    }

    private static func searxng(_ q: String, base: String, limit: Int, session: URLSession) async throws -> [WebSearchResult] {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: base.trimmingCharacters(in: .whitespaces).trimmingSlash + "/search?q=\(enc)&format=json") else { throw WebSearchError.badURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await get(req, session: session)
        struct R: Decodable { struct Item: Decodable { let title: String?; let url: String?; let content: String? }; let results: [Item]? }
        let decoded = try JSONDecoder().decode(R.self, from: data)
        return (decoded.results ?? []).prefix(limit).map {
            WebSearchResult(title: $0.title ?? "", url: $0.url ?? "", snippet: clean($0.content ?? ""))
        }
    }

    private static func get(_ req: URLRequest, session: URLSession) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw WebSearchError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw WebSearchError.http(http.statusCode) }
        return data
    }

    // MARK: page fetch

    /// Fetch a page and reduce it to readable text (dependency-free HTML strip), capped.
    public static func fetchText(_ url: URL, maxChars: Int = 8000, session: URLSession) async throws -> String {
        guard url.scheme?.hasPrefix("http") == true else { throw WebSearchError.badURL }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (compatible; SlateBot)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebSearchError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        return String(stripHTML(html).prefix(maxChars))
    }

    private static func stripHTML(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg"] {
            s = s.replacingOccurrences(of: "(?s)<\(tag).*?</\(tag)>", with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?s)<!--.*?-->", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\s*\\n\\s*){2,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: agent tools

    /// Build `web_search` + `fetch_url` RegisteredTools for an agent loop.
    public static func tools(config: WebSearchConfig, session: URLSession) -> [RegisteredTool] {
        let searchTool = RegisteredTool(spec: ToolSpec(
            name: "web_search",
            description: "Search the web for current or factual information. Returns ranked results with title, URL and a snippet. Use fetch_url afterwards to read a promising page in full.",
            parameters: [ToolParameter(name: "query", description: "The search query.", required: true)])
        ) { args in
            guard let query = args["query"], !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "Error: a non-empty 'query' is required."
            }
            do {
                let results = try await Self.search(query, config: config, session: session)
                guard !results.isEmpty else { return "No results found." }
                return results.enumerated().map { i, r in
                    "\(i + 1). \(r.title)\n\(r.url)\n\(r.snippet)"
                }.joined(separator: "\n\n")
            } catch {
                return "Web search failed: \(error.localizedDescription)"
            }
        }
        let fetchTool = RegisteredTool(spec: ToolSpec(
            name: "fetch_url",
            description: "Fetch the readable text of a web page by URL (use after web_search).",
            parameters: [ToolParameter(name: "url", description: "The http(s) URL to fetch.", required: true)])
        ) { args in
            guard let raw = args["url"], let url = URL(string: raw.trimmingCharacters(in: .whitespaces)) else {
                return "Error: a valid 'url' is required."
            }
            do { return try await Self.fetchText(url, session: session) }
            catch { return "Fetch failed: \(error.localizedDescription)" }
        }
        return [searchTool, fetchTool]
    }
}

private extension String {
    var trimmingSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}
