import Foundation

/// One durable fact Slate remembers about the user across sessions.
public struct UserMemory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    /// Where it was learned (conversation title) - shown in Settings.
    public var source: String?
    /// Disabled memories stay listed but are never injected.
    public var enabled: Bool

    public init(text: String, source: String? = nil,
                createdAt: Date = Date(), enabled: Bool = true) {
        self.id = UUID()
        self.text = text
        self.source = source
        self.createdAt = createdAt
        self.enabled = enabled
    }
}

/// Slate's long-term memory: a small, user-visible list of facts injected into
/// chat/voice system prompts. Fully offline - one JSON file, editable in
/// Settings, hard-capped so the prompt block stays small.
public struct MemoryStore: Sendable {
    public private(set) var entries: [UserMemory] = []
    public static let cap = 100

    public init() {}
    public init(entries: [UserMemory]) { self.entries = entries }

    /// Adds a fact unless it near-duplicates an existing one (normalized exact
    /// or containment match). Oldest entries fall off beyond the cap.
    @discardableResult
    public mutating func add(_ text: String, source: String?) -> UserMemory? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let normNew = Self.normalize(t)
        for e in entries {
            let normOld = Self.normalize(e.text)
            if normOld == normNew || normOld.contains(normNew) || normNew.contains(normOld) {
                return nil
            }
        }
        let m = UserMemory(text: t, source: source)
        entries.append(m)
        if entries.count > Self.cap { entries.removeFirst(entries.count - Self.cap) }
        return m
    }

    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func removeAll() { entries = [] }

    /// Replace an entry (toggle enabled / edit text from Settings).
    public mutating func replace(_ memory: UserMemory) {
        guard let i = entries.firstIndex(where: { $0.id == memory.id }) else { return }
        entries[i] = memory
    }

    /// System-prompt block with the newest enabled facts, or nil when none.
    public func promptBlock(limit: Int = 30) -> String? {
        let active = entries.filter(\.enabled).suffix(max(limit, 0))
        guard !active.isEmpty else { return nil }
        let lines = active.map { "- \($0.text)" }.joined(separator: "\n")
        return "Things you know about the user from earlier conversations (use naturally when relevant, never recite the list):\n\(lines)"
    }

    /// Validates a raw model extraction into a storable fact, or nil.
    /// Strips bullets/quotes, keeps the first line, rejects NONE / empties /
    /// walls of text (a memory is one short sentence).
    public static func sanitizeExtraction(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.components(separatedBy: .newlines).first ?? s
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-•* \t\"'`“”"))
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 240 else { return nil }
        let lowered = s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard lowered != "none", lowered != "nichts", lowered != "keine" else { return nil }
        return s
    }

    // MARK: persistence

    public static func load(from url: URL) -> MemoryStore {
        guard let data = try? PrivateStorage.read(from: url, maxBytes: 1_000_000),
              let entries = try? JSONDecoder().decode([UserMemory].self, from: data) else {
            return MemoryStore()
        }
        return MemoryStore(entries: Array(entries.suffix(cap)))
    }

    public func save(to url: URL) {
        if let data = try? JSONEncoder().encode(entries) {
            try? PrivateStorage.write(data, to: url)
        }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
