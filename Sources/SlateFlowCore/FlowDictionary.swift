import Foundation
import SlateCore

/// Personal dictionary (spec item 9): names, jargon, wrong→right mappings.
/// Entries with a `wrong` side are deterministic post-STT replacements
/// (word-boundary, case-insensitive, longest first); entries with only a
/// `right` side are vocabulary hints fed into the cleanup prompt.
public struct FlowDictionary: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Codable, Identifiable {
        public var id: UUID
        /// Misheard form ("lange und co"); empty = prompt-vocabulary-only term.
        public var wrong: String
        /// Canonical form ("Lange & Co.").
        public var right: String
        public init(id: UUID = UUID(), wrong: String, right: String) {
            self.id = id; self.wrong = wrong; self.right = right
        }
    }

    public var entries: [Entry]
    public init(entries: [Entry] = []) { self.entries = entries }

    /// Terms the cleanup prompt should know as preferred spellings.
    public var promptTerms: [String] {
        entries.map(\.right).filter { !$0.isEmpty }
    }

    /// Deterministic replacement pass over a transcript.
    public func apply(to text: String) -> String {
        var s = text
        let replacements = entries
            .filter { !$0.wrong.isEmpty && !$0.right.isEmpty }
            .sorted { $0.wrong.count > $1.wrong.count }        // longest wins
        for e in replacements {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: e.wrong) + #"\b"#
            s = s.replacingOccurrences(of: pattern, with: e.right,
                                       options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    // MARK: Persistence

    public static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slate/flow-dictionary.json")
    }

    public static func load(from url: URL = storeURL) -> FlowDictionary {
        guard let data = try? PrivateStorage.read(from: url, maxBytes: 1_000_000),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return FlowDictionary()
        }
        return FlowDictionary(entries: Array(entries.prefix(1_000)))
    }

    public func save(to url: URL = Self.storeURL) {
        if let data = try? JSONEncoder().encode(entries) { try? PrivateStorage.write(data, to: url) }
    }
}
