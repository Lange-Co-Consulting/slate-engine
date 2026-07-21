import Foundation

public struct AuditEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let action: String
    public let detail: String
    public let approval: String
    public let outcome: String

    public init(category: String, action: String, detail: String,
                approval: String, outcome: String, now: Date = Date()) {
        self.id = UUID()
        self.timestamp = now
        self.category = category
        self.action = action
        self.detail = detail
        self.approval = approval
        self.outcome = outcome
    }
}

/// Local append-only JSONL audit trail. It intentionally never records tool
/// output, conversation text, memory, or file contents.
public enum AuditLog {
    private static let lock = NSLock()
    private static let maxBytes = 2_000_000

    public static var fileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Slate", isDirectory: true)
            .appendingPathComponent("audit.log")
    }

    public static func record(_ entry: AuditEntry) {
        lock.withLock {
            let url = fileURL
            guard var line = try? JSONEncoder().encode(entry) else { return }
            line.append(0x0A)
            guard line.count <= maxBytes else { return }
            // Keep the audit trail bounded: a maliciously chatty tool must not
            // be able to exhaust the user's disk through diagnostic metadata.
            var data = (try? PrivateStorage.read(from: url, maxBytes: maxBytes)) ?? Data()
            let keep = max(0, maxBytes - line.count)
            if data.count > keep {
                let start = data.index(data.endIndex, offsetBy: -keep)
                data = Data(data[start...])
                if let newline = data.firstIndex(of: 0x0A) {
                    data.removeSubrange(...newline)
                } else { data = Data() }
            }
            data.append(line)
            try? PrivateStorage.write(data, to: url)
        }
    }

    public static func recent(limit: Int = 250) -> [AuditEntry] {
        lock.withLock {
            guard let data = try? PrivateStorage.read(from: fileURL, maxBytes: maxBytes),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n")
                .suffix(max(0, min(limit, 5_000)))
                .compactMap { try? JSONDecoder().decode(AuditEntry.self, from: Data($0.utf8)) }
        }
    }

    public static func clear() throws {
        try lock.withLock {
            try PrivateStorage.write(Data(), to: fileURL)
        }
    }
}
