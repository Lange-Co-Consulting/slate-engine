import Testing
import Foundation
@testable import SlateLlama
import SlateCore

private func fixture() throws -> (URL, WorkspaceScope) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("slate-ft-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("src"),
                                            withIntermediateDirectories: true)
    try "let answer = 42\nprint(answer)\n"
        .write(to: root.appendingPathComponent("src/main.swift"), atomically: true, encoding: .utf8)
    try "# Readme\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    return (root, WorkspaceScope(root: root))
}

@Test func readFileReturnsContent() throws {
    let (_, scope) = try fixture()
    let tools = FileTools(scope: scope)
    let text = try tools.readFile(path: "src/main.swift", lineRange: nil)
    #expect(text.contains("let answer = 42"))
}

@Test func readFileRejectsEscape() throws {
    let (_, scope) = try fixture()
    let tools = FileTools(scope: scope)
    #expect(throws: (any Error).self) {
        _ = try tools.readFile(path: "../../../etc/hosts", lineRange: nil)
    }
}

@Test func readFileRejectsOversizedContent() throws {
    let (root, scope) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(repeating: 65, count: FileTools.maxReadBytes + 1)
        .write(to: root.appendingPathComponent("too-large.txt"))
    let tools = FileTools(scope: scope)
    #expect(throws: FileToolsError.self) {
        _ = try tools.readFile(path: "too-large.txt", lineRange: nil)
    }
}

@Test func listReturnsRelativePaths() throws {
    let (_, scope) = try fixture()
    let tools = FileTools(scope: scope)
    let files = try tools.list(glob: nil)
    #expect(files.contains("src/main.swift"))
    #expect(files.contains("README.md"))
}

@Test func searchFindsMatches() throws {
    let (_, scope) = try fixture()
    let tools = FileTools(scope: scope)
    let hits = try tools.search(query: "answer")
    #expect(hits.contains { $0.contains("src/main.swift") && $0.contains("answer") })
}
