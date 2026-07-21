import Testing
import Foundation
@testable import SlateLlama
import SlateCore

private func repoFixture() throws -> WorkspaceScope {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("slate-edit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "let x = 1\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
    return WorkspaceScope(root: root)
}

private let blockText = """
a.swift
```swift
<<<<<<< SEARCH
let x = 1
=======
let x = 99
>>>>>>> REPLACE
```
"""

@Test func editToolAppliesApprovedEdit() async throws {
    let scope = try repoFixture()
    let tool = EditTool(scope: scope, gate: AutoApproveGate(), mode: { .autopilot })
    let result = try await tool.apply(blockText)
    let onDisk = try String(contentsOf: scope.resolve("a.swift"), encoding: .utf8)
    #expect(onDisk.contains("let x = 99"))
    #expect(result.contains("a.swift"))
}

@Test func editToolRejectedWhenGateDenies() async throws {
    struct DenyGate: ApprovalGate { func confirm(_ r: ApprovalRequest) async -> Bool { false } }
    let scope = try repoFixture()
    let tool = EditTool(scope: scope, gate: DenyGate(), mode: { .ask })
    _ = try await tool.apply(blockText)
    let onDisk = try String(contentsOf: scope.resolve("a.swift"), encoding: .utf8)
    #expect(onDisk.contains("let x = 1"))   // unchanged
}
