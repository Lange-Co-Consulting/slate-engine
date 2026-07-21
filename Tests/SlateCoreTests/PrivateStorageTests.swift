import Foundation
import Testing
@testable import SlateCore

@Suite struct PrivateStorageTests {
    @Test func writesPrivateFileAndDirectory() throws {
        let root = URL.temporaryDirectory.appendingPathComponent("slate-private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("nested/value.json")

        try PrivateStorage.write(Data("secret".utf8), to: file)

        let dirMode = try #require(FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)
        let fileMode = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        #expect(dirMode.intValue & 0o777 == 0o700)
        #expect(fileMode.intValue & 0o777 == 0o600)
        #expect(try PrivateStorage.read(from: file, maxBytes: 64) == Data("secret".utf8))
    }

    @Test func rejectsSymbolicLinkDestination() throws {
        let root = URL.temporaryDirectory.appendingPathComponent("slate-private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try PrivateStorage.ensureDirectory(root)
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("link")
        try Data("unchanged".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: PrivateStorage.StorageError.self) {
            try PrivateStorage.write(Data("changed".utf8), to: link)
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "unchanged")
    }

    @Test func readRejectsLinksAndOversizedFiles() throws {
        let root = URL.temporaryDirectory.appendingPathComponent("slate-private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try PrivateStorage.ensureDirectory(root)
        let target = root.appendingPathComponent("target")
        let link = root.appendingPathComponent("link")
        try PrivateStorage.write(Data(repeating: 1, count: 32), to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: PrivateStorage.StorageError.self) {
            try PrivateStorage.read(from: link, maxBytes: 64)
        }
        #expect(throws: PrivateStorage.StorageError.self) {
            try PrivateStorage.read(from: target, maxBytes: 16)
        }
    }
}
