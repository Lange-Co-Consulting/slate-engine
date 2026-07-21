import Foundation

/// Trims a chat history to fit under a token budget WITHOUT mutating the stored
/// conversation: system messages are always kept, then the newest turns are kept
/// and the oldest dropped until it fits. A rough estimate (chars/4 + per-message
/// overhead) is enough — the caller leaves headroom and the engine keeps a hard
/// backstop.
public enum ContextBudget {
    /// ~4 chars per token plus a small per-message framing overhead.
    public static func estimateTokens(_ message: ChatMessage) -> Int {
        message.content.count / 4 + 8
    }

    /// Returns the messages to send and how many were dropped. `budget <= 0`
    /// disables trimming (unknown context window → send everything).
    public static func trim(_ messages: [ChatMessage],
                            approxTokenBudget budget: Int) -> (kept: [ChatMessage], trimmed: Int) {
        guard budget > 0 else { return (messages, 0) }
        let systems = messages.filter { $0.role == .system }
        let rest = messages.filter { $0.role != .system }
        var remaining = budget - systems.reduce(0) { $0 + estimateTokens($1) }
        var keptReversed: [ChatMessage] = []
        for message in rest.reversed() {
            let cost = estimateTokens(message)
            if keptReversed.isEmpty || cost <= remaining {
                keptReversed.append(message)   // always keep at least the newest
                remaining -= cost
            } else {
                break
            }
        }
        let kept = systems + keptReversed.reversed()
        return (kept, rest.count - keptReversed.count)
    }
}
