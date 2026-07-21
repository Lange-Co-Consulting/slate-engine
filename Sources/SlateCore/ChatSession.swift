public struct ChatSession: Sendable, Equatable {
    public private(set) var messages: [ChatMessage] = []

    public init(system: String? = nil) {
        if let system {
            messages.append(ChatMessage(role: .system, content: system))
        }
    }

    /// Appends a message; assistant turns have their reasoning stripped
    /// before storage so it never re-enters a future prompt.
    public mutating func append(_ message: ChatMessage) {
        if message.role == .assistant {
            messages.append(ChatMessage(role: .assistant,
                                        content: ChatSession.stripThink(message.content)))
        } else {
            messages.append(message)
        }
    }

    /// The messages to feed into the next prompt (already stripped on store).
    public func messagesForPrompt() -> [ChatMessage] { messages }

    /// Removes hidden reasoning before re-feeding into a prompt: every
    /// `<think>…</think>` block, harmony/channel reasoning, and stray control
    /// tokens. Delegates to `Reasoning.strip`.
    public static func stripThink(_ text: String) -> String {
        Reasoning.strip(text)
    }
}
