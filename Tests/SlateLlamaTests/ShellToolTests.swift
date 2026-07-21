import Testing
import Foundation
@testable import SlateLlama
import SlateCore

private func tmpRoot() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("slate-sh-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func runsAndStreamsOutput() async throws {
    let tool = ShellTool(workspaceRoot: tmpRoot())
    var out = ""
    for try await chunk in tool.run("echo hello-slate") { out += chunk }
    #expect(out.contains("hello-slate"))
}

@Test func blockedCommandThrows() async {
    let tool = ShellTool(workspaceRoot: tmpRoot())
    await #expect(throws: (any Error).self) {
        for try await _ in tool.run("rm -rf /") {}
    }
}

/// A non-zero exit must NOT throw — the agent needs the output (a failing
/// build/test, `grep` with no match) to self-correct. Regression guard: an
/// earlier change threw on non-zero exit, discarding all captured output.
@Test func nonZeroExitKeepsOutputAndReportsCode() async throws {
    let tool = ShellTool(workspaceRoot: tmpRoot())
    var out = ""
    for try await chunk in tool.run("echo before-fail; exit 3") { out += chunk }
    #expect(out.contains("before-fail"))
    #expect(out.contains("exit status 3"))
}

@Test func runsInWorkspaceCwd() async throws {
    let root = tmpRoot()
    try "workspace-only".write(to: root.appendingPathComponent("scope-proof.txt"), atomically: true, encoding: .utf8)
    let tool = ShellTool(workspaceRoot: root)
    var out = ""
    for try await chunk in tool.run("cat scope-proof.txt") { out += chunk }
    #expect(out.contains("workspace-only"))
}

@Test func sandboxProfileEscapesWorkspaceAndDeniesNetwork() {
    let workspace = URL(fileURLWithPath: "/tmp/a\"quoted")
    let scratch = URL(fileURLWithPath: "/tmp/scratch")
    let profile = WorkspaceSandbox.profile(workspace: workspace, scratch: scratch)
    #expect(profile.contains("deny network"))
    #expect(profile.contains(#"/tmp/a\"quoted"#))
    #expect(!profile.contains("allow default"))
}
