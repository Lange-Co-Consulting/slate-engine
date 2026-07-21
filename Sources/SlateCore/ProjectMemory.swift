import Foundation
import CryptoKit

/// One durable, learned fact about a specific project (a build/test command that
/// works, a convention, an architecture decision, a gotcha). The code agent
/// accumulates these across sessions so it stops rediscovering the basics.
public struct ProjectFact: Codable, Equatable, Sendable {
    public var text: String
    public let createdAt: Date
    public init(text: String, createdAt: Date = Date()) {
        self.text = text
        self.createdAt = createdAt
    }
}

/// Per-project memory: a small list of facts stored OUTSIDE the repo (in Slate's
/// app-support, keyed by the workspace path) so it never pollutes the user's git
/// tree. Mirrors `MemoryStore` but scoped to one folder, and hard-capped so the
/// injected system-prompt block stays small.
public struct ProjectMemory: Sendable, Equatable {
    public private(set) var facts: [ProjectFact]
    public static let cap = 40

    public init(facts: [ProjectFact] = []) { self.facts = facts }

    /// Add a fact unless it near-duplicates an existing one (normalized exact or
    /// containment match). Oldest entries fall off beyond the cap. Returns whether
    /// it was actually stored.
    @discardableResult
    public mutating func add(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let n = Self.normalize(t)
        for f in facts {
            let o = Self.normalize(f.text)
            if o == n || o.contains(n) || n.contains(o) { return false }
        }
        facts.append(ProjectFact(text: t))
        if facts.count > Self.cap { facts.removeFirst(facts.count - Self.cap) }
        return true
    }

    public mutating func remove(at index: Int) {
        guard facts.indices.contains(index) else { return }
        facts.remove(at: index)
    }

    /// Remove the fact with this exact text (facts are unique per project).
    public mutating func removeFact(_ text: String) {
        facts.removeAll { $0.text == text }
    }

    /// Validate a raw model-supplied fact into a storable one, or nil. Keeps the
    /// first line, strips bullets/quotes, rejects empties / NONE / walls of text.
    public static func sanitize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.components(separatedBy: .newlines).first ?? s
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t\"'`“”"))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 240 else { return nil }
        let low = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard low != "none", low != "nichts", low != "keine" else { return nil }
        return s
    }

    /// System-prompt block: the known facts, plus (when the agent can persist new
    /// ones) a short instruction teaching the `remember_project_fact` tool.
    public static func augment(systemPrompt base: String, with memory: ProjectMemory?, canRemember: Bool) -> String {
        var out = base
        if let facts = memory?.facts, !facts.isEmpty {
            let lines = facts.suffix(cap).map { "- \($0.text)" }.joined(separator: "\n")
            out += "\n\nKnown facts about THIS project (learned in earlier sessions - use them, don't rediscover the basics):\n\(lines)"
        }
        if canRemember {
            out += "\n\nWhen you learn a durable fact about this project - a build or test command that works, a convention, an architecture decision, a gotcha - call remember_project_fact {\"fact\": \"…\"} with ONE short fact so future sessions know it. Do not re-store a fact already listed above."
        }
        return out
    }

    // MARK: persistence (one small JSON per project, outside the repo)

    public static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slate/ProjectMemory", isDirectory: true)
        try? PrivateStorage.ensureDirectory(base)
        return base
    }

    /// Stable, filesystem-safe key for a workspace path (SHA-256 hex).
    public static func key(for folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        return SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func url(for folder: URL) -> URL {
        directory().appendingPathComponent(key(for: folder) + ".json")
    }

    public static func load(for folder: URL) -> ProjectMemory {
        guard let data = try? PrivateStorage.read(from: url(for: folder), maxBytes: 1_000_000) else {
            return ProjectMemory()
        }
        let dec = JSONDecoder()
        if let file = try? dec.decode(ProjectMemoryFile.self, from: data) {
            return ProjectMemory(facts: Array(file.facts.suffix(cap)))
        }
        if let facts = try? dec.decode([ProjectFact].self, from: data) {   // legacy (path-less) format
            return ProjectMemory(facts: Array(facts.suffix(cap)))
        }
        return ProjectMemory()
    }

    /// Persist facts alongside the workspace path, so Settings can show WHICH
    /// project each fact set belongs to (the filename itself is only a hash).
    public func save(for folder: URL) {
        let file = ProjectMemoryFile(folderPath: folder.standardizedFileURL.path, facts: facts)
        if let data = try? JSONEncoder().encode(file) {
            try? PrivateStorage.write(data, to: Self.url(for: folder))
        }
    }

    // MARK: management (Settings)

    /// Every project that has stored facts, newest-path-sorted, for the Settings list.
    public static func allProjects() -> [ProjectMemorySummary] {
        let dir = directory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [ProjectMemorySummary] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? PrivateStorage.read(from: f, maxBytes: 1_000_000),
                  let file = try? JSONDecoder().decode(ProjectMemoryFile.self, from: data),
                  !file.facts.isEmpty else { continue }
            out.append(ProjectMemorySummary(folderPath: file.folderPath,
                                            facts: Array(file.facts.suffix(cap))))
        }
        return out.sorted { $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending }
    }

    /// Delete all remembered facts for one project.
    public static func clear(folderPath: String) {
        try? FileManager.default.removeItem(at: url(for: URL(fileURLWithPath: folderPath)))
    }

    /// Forget a single fact for a project (deletes the file if it was the last).
    public static func removeFact(text: String, folderPath: String) {
        let folder = URL(fileURLWithPath: folderPath)
        var pm = load(for: folder)
        pm.removeFact(text)
        if pm.facts.isEmpty { clear(folderPath: folderPath) } else { pm.save(for: folder) }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// On-disk record: the workspace path plus its facts (the file's name is a hash,
/// so the path is stored inside for the Settings UI to display).
private struct ProjectMemoryFile: Codable {
    var folderPath: String
    var facts: [ProjectFact]
}

/// One project's remembered facts, for the Settings management list.
public struct ProjectMemorySummary: Identifiable, Sendable, Equatable {
    public var id: String { folderPath }
    public let folderPath: String
    public let facts: [ProjectFact]
    public var name: String { URL(fileURLWithPath: folderPath).lastPathComponent }
    public init(folderPath: String, facts: [ProjectFact]) {
        self.folderPath = folderPath
        self.facts = facts
    }
}
