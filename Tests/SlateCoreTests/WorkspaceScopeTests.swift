import Testing
import Foundation
@testable import SlateCore

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory
        .appendingPathComponent("slate-ws-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func resolvesPathInsideRoot() throws {
    let root = tempDir()
    let scope = WorkspaceScope(root: root)
    let url = try scope.resolve("src/main.swift")
    #expect(url.path.hasPrefix(root.resolvingSymlinksInPath().path))
}

@Test func rejectsParentEscape() {
    let scope = WorkspaceScope(root: tempDir())
    #expect(throws: WorkspaceScope.ScopeError.self) {
        _ = try scope.resolve("../../etc/passwd")
    }
}

@Test func rejectsSiblingPrefixCollision() {
    let base = tempDir()
    let proj = base.appendingPathComponent("proj")
    try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
    let scope = WorkspaceScope(root: proj)
    #expect(throws: WorkspaceScope.ScopeError.self) {
        _ = try scope.resolve("../proj-evil/x")
    }
}

@Test func containsRootItself() {
    let root = tempDir()
    let scope = WorkspaceScope(root: root)
    #expect(scope.contains(root))
}
