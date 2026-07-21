import Foundation

/// Pure planning + prompt building for `/compact`. The actual model call and the
/// conversation rewrite live in AppModel (needs the engine + persistence); this
/// stays unit-testable.
public enum CompactService {
    public struct Plan: Equatable {
        public let systemCount: Int
        public let toSummarize: [ChatMessage]   // older half, replaced by a summary
        public let keep: [ChatMessage]          // most-recent, kept verbatim
    }

    /// Keep all system messages + the `keepRecent` newest non-system turns; the
    /// rest (the older half) is what gets summarized.
    public static func plan(messages: [ChatMessage], keepRecent: Int = 6) -> Plan {
        let systems = messages.filter { $0.role == .system }
        let rest = messages.filter { $0.role != .system }
        guard rest.count > keepRecent else {
            return Plan(systemCount: systems.count, toSummarize: [], keep: rest)
        }
        let split = rest.count - keepRecent
        return Plan(systemCount: systems.count,
                    toSummarize: Array(rest[..<split]),
                    keep: Array(rest[split...]))
    }

    public static func summaryPrompt(for messages: [ChatMessage]) -> String {
        let transcript = messages.map { "\($0.role.rawValue.uppercased()): \($0.content)" }
            .joined(separator: "\n\n")
        return """
        Summarize the earlier part of this conversation into a compact briefing that
        preserves decisions, facts, open questions and any code/file references, so the
        assistant can continue seamlessly. Be concise; use short bullet points.

        --- transcript to summarize ---
        \(transcript)
        --- end transcript ---

        Compact summary:
        """
    }
}
