import Foundation

public struct ChatMessage: Equatable, Sendable, Identifiable, Codable {
    public enum Role: String, Sendable, Equatable, Codable {
        case system, user, assistant, tool
    }

    public let id: UUID
    public let role: Role
    public var content: String
    /// Absolute path to an attached image for vision-capable models (user turns only). nil = text-only.
    public var imagePath: String?
    /// Generation stats for assistant turns ("≈420 tok · 38 t/s · 11s"). Optional →
    /// old saved conversations decode fine.
    public var stats: String?
    /// Agent Chat (roundtable): the model/persona that produced this assistant turn,
    /// plus a stable 0-based index for per-speaker coloring. nil for ordinary chat/code
    /// turns. Optional → old conversations decode unchanged (synthesized Codable).
    public var speaker: String?
    public var speakerIndex: Int?

    public init(id: UUID = UUID(), role: Role, content: String, imagePath: String? = nil,
                stats: String? = nil, speaker: String? = nil, speakerIndex: Int? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePath = imagePath
        self.stats = stats
        self.speaker = speaker
        self.speakerIndex = speakerIndex
    }

    // Equality ignores id so tests can compare by role+content.
    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.role == rhs.role && lhs.content == rhs.content
    }
}
