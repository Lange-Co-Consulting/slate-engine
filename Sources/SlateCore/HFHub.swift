import Foundation

/// HuggingFace Hub API: search GGUF repos and list their files, so the in-app
/// model manager can browse the whole Hub, not just the curated catalog.
/// Pure request-building + parsing (unit-testable); networking lives in the app.
public enum HFHub {
    public struct Repo: Codable, Identifiable, Sendable, Equatable {
        public let id: String          // "unsloth/Qwen3.5-9B-GGUF"
        public let downloads: Int?
        public let likes: Int?
        public let trendingScore: Int?
        public init(id: String, downloads: Int? = nil, likes: Int? = nil, trendingScore: Int? = nil) {
            self.id = id; self.downloads = downloads; self.likes = likes; self.trendingScore = trendingScore
        }
    }

    public struct TreeItem: Codable, Sendable, Equatable {
        public let type: String        // "file" | "directory"
        public let path: String        // may contain subfolders ("UD/model.gguf")
        public let size: Int64?
    }

    /// A downloadable GGUF inside a repo.
    public struct GGUFFile: Identifiable, Sendable, Equatable {
        public let repo: String
        public let path: String
        public let bytes: Int64
        public var id: String { repo + "/" + path }
        public var fileName: String { (path as NSString).lastPathComponent }
        /// Vision projector companion (mmproj) rather than a chat model.
        public var isProjector: Bool { fileName.lowercased().contains("mmproj") }
        public var downloadURL: URL? { HFHub.resolveURL(repo: repo, path: path) }
    }

    // MARK: request building

    public static func searchURL(query: String, limit: Int = 25) -> URL? {
        var c = URLComponents(string: "https://huggingface.co/api/models")
        c?.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return c?.url
    }

    /// The Hub's "trending now" GGUF repos (live-verified: sort=trendingScore).
    public static func trendingURL(limit: Int = 50) -> URL? {
        var c = URLComponents(string: "https://huggingface.co/api/models")
        c?.queryItems = [
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "trendingScore"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return c?.url
    }

    public static func treeURL(repo: String) -> URL? {
        guard let path = encodePath("api/models/\(repo)/tree/main") else { return nil }
        return URL(string: "https://huggingface.co/\(path)?recursive=true")
    }

    public static func resolveURL(repo: String, path: String) -> URL? {
        guard let p = encodePath("\(repo)/resolve/main/\(path)") else { return nil }
        return URL(string: "https://huggingface.co/\(p)")
    }

    /// Percent-encode each path segment, keeping the "/" separators.
    private static func encodePath(_ path: String) -> String? {
        let segs = path.split(separator: "/", omittingEmptySubsequences: true)
        let enc = segs.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        guard enc.count == segs.count else { return nil }
        return enc.joined(separator: "/")
    }

    // MARK: parsing

    public static func parseRepos(_ data: Data) -> [Repo] {
        // Lenient on purpose. The Hub returns `trendingScore` (and occasionally
        // other counters) as a NON-integer number for lower-ranked models, and a
        // strict `decode([Repo].self)` is all-or-nothing: one fractional score
        // would drop the ENTIRE list — the "trending stays empty" bug, invisible
        // at limit=5 (integer top scores) but hit at limit=50. Parse element by
        // element, coerce numbers, and skip only entries without a usable id.
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { obj in
            guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
            return Repo(id: id,
                        downloads: intValue(obj["downloads"]),
                        likes: intValue(obj["likes"]),
                        trendingScore: intValue(obj["trendingScore"]))
        }
    }

    /// Coerce a JSON value to Int, tolerating integer OR fractional numbers (the
    /// Hub sends both) and numeric strings; nil for anything else/absent.
    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    public static func parseTree(_ data: Data) -> [TreeItem] {
        (try? JSONDecoder().decode([TreeItem].self, from: data)) ?? []
    }

    /// The GGUF files of a repo: chat models first (smallest quant first, so the
    /// fitting ones lead), projectors at the end.
    public static func ggufFiles(repo: String, tree: [TreeItem]) -> [GGUFFile] {
        let files = tree
            .filter { $0.type == "file" && $0.path.lowercased().hasSuffix(".gguf") }
            .map { GGUFFile(repo: repo, path: $0.path, bytes: $0.size ?? 0) }
        let models = files.filter { !$0.isProjector }.sorted { $0.bytes < $1.bytes }
        let projectors = files.filter(\.isProjector).sorted { $0.bytes < $1.bytes }
        return models + projectors
    }
}
