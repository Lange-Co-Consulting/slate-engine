import Foundation

/// Import the most recent Claude Code session for a project folder, so Slate can
/// continue exactly where Claude Code left off when the limit is hit.
///
/// Claude Code stores sessions as JSONL under `~/.claude/projects/<encoded>/*.jsonl`,
/// where `<encoded>` is the absolute folder path with every `/` replaced by `-`.
public enum ClaudeCodeImport {
    private static let maxSessionBytes = 5 * 1_024 * 1_024
    private static let maxMessages = 500
    private static let maxMessageCharacters = 16_000
    public struct Session: Identifiable, Sendable, Equatable {
        public let id: String          // file path
        public let title: String       // first user line, snipped
        public let modified: Date
        public let messageCount: Int
        public let fileURL: URL
    }

    public static func projectsDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// `/Users/x/Proj` -> `-Users-x-Proj`
    public static func encode(_ folder: URL) -> String {
        var p = folder.standardizedFileURL.path
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p.replacingOccurrences(of: "/", with: "-")
    }

    /// Recent sessions for a folder, newest first.
    public static func sessions(forFolder folder: URL, projectsDir base: URL? = nil) -> [Session] {
        let dir = (base ?? projectsDir()).appendingPathComponent(encode(folder), isDirectory: true)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return [] }
        return items.prefix(100)
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> Session? in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let msgs = messages(from: url)
                guard !msgs.isEmpty else { return nil }
                let firstUser = msgs.first { $0.role == .user }?.content ?? msgs.first?.content ?? "Session"
                return Session(id: url.path, title: snip(firstUser, 60), modified: mod,
                               messageCount: msgs.count, fileURL: url)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Parse a session JSONL into user/assistant text turns (tool noise skipped).
    public static func messages(from fileURL: URL) -> [ChatMessage] {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize, size <= maxSessionBytes,
              let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var out: [ChatMessage] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // The message can be at top level (.message) - tolerate either shape.
            let message = (obj["message"] as? [String: Any]) ?? obj
            guard let role = message["role"] as? String,
                  role == "user" || role == "assistant",
                  let text = extractText(message["content"]), !text.isEmpty else { continue }
            out.append(ChatMessage(role: role == "user" ? .user : .assistant,
                                   content: String(text.prefix(maxMessageCharacters))))
            if out.count >= maxMessages { break }
        }
        return out
    }

    /// The tail of a conversation that fits within a character budget - what we seed
    /// into the new Slate session so the local (smaller) context isn't blown.
    public static func recentTail(_ messages: [ChatMessage], budget: Int = 8000) -> [ChatMessage] {
        var total = 0
        var tail: [ChatMessage] = []
        for m in messages.reversed() {
            total += m.content.count
            if total > budget && !tail.isEmpty { break }
            tail.insert(m, at: 0)
        }
        return tail
    }

    // MARK: - Helpers

    private static func extractText(_ content: Any?) -> String? {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            let texts = arr.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func snip(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }
}
