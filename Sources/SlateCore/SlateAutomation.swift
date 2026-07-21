import Foundation

public struct SlateAutomationRequest: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable { case ask }
    public let id: UUID
    public let action: Action
    public let text: String

    public init(id: UUID = UUID(), action: Action, text: String) {
        self.id = id; self.action = action; self.text = text
    }
}

public struct SlateAutomationResponse: Codable, Sendable, Equatable {
    public let id: UUID
    public let result: String?
    public let error: String?

    public init(id: UUID, result: String? = nil, error: String? = nil) {
        self.id = id; self.result = result; self.error = error
    }
}

/// File-based localhost IPC shared by slatectl and Slate.app. Fixed UUID file
/// names avoid putting prompts in URLs, shell arguments, or process listings.
public enum SlateAutomation {
    public static var root: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Slate/Automation", isDirectory: true)
    }
    public static var inbox: URL { root.appendingPathComponent("Inbox", isDirectory: true) }
    public static var outbox: URL { root.appendingPathComponent("Outbox", isDirectory: true) }

    public static func requestURL(for id: UUID) -> URL {
        inbox.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    public static func responseURL(for id: UUID) -> URL {
        outbox.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    public static func prepareDirectories() throws {
        for directory in [root, inbox, outbox] {
            try PrivateStorage.ensureDirectory(directory)
        }
    }

    public static func id(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "slate",
              url.host?.lowercased() == "automation" else { return nil }
        let raw = url.pathComponents.last ?? ""
        return UUID(uuidString: raw)
    }
}
