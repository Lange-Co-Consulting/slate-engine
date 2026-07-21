import Testing
import Foundation
@testable import SlateLlama
import SlateCore

private struct AgentSmokeError: Error { let msg: String }
private struct AutoApproveGate: ApprovalGate {
    func confirm(_ request: ApprovalRequest) async -> Bool { true }
}

/// Real end-to-end agentic check: a local model must actually CREATE a file in the
/// workspace (not paste code into the chat). Proves the eager JSON tool-call grammar
/// parses in llama and the write_file tool fires.
///   SLATE_AGENT_SMOKE=1 SLATE_TEST_MODEL=~/Models/Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf swift test
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLATE_AGENT_SMOKE"] == "1"))
func agentActuallyCreatesAFile() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["SLATE_TEST_MODEL"] else {
        throw AgentSmokeError(msg: "SLATE_TEST_MODEL unset")
    }
    let ngl = ProcessInfo.processInfo.environment["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 999
    let engine = try LlamaEngine(modelPath: modelPath, nCtx: 8192, nGpuLayers: ngl)

    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-agent-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let scope = WorkspaceScope(root: dir)
    let registry = SlateAgentFactory.fullRegistry(scope: scope, gate: AutoApproveGate(), mode: { .autopilot })

    var session = ChatSession(system: SlateAgentFactory.systemPrompt())
    session.append(ChatMessage(role: .user,
        content: "Create a file named hello.html containing a minimal HTML5 page whose <h1> says \"Hello Slate\". Then finish."))

    let loop = AgentLoop(engine: engine, registry: registry, maxIterations: 8)
    var activity: [String] = []
    var finalAnswer = ""
    for try await event in loop.run(session: session) {
        switch event {
        case .toolCall(let n, let a): activity.append("\(n) \(a["path"] ?? a["command"] ?? a["query"] ?? "")")
        case .toolResult(let n, let o): activity.append("  ↳ \(n): \(o.split(separator: "\n").first ?? "")")
        case .finalAnswer(let t): finalAnswer = t
        case .failed(let m): activity.append("FAILED: \(m)")
        default: break
        }
    }
    print("=== AGENT ACTIVITY ===\n\(activity.joined(separator: "\n"))\n=== FINAL ===\n\(finalAnswer)")

    let created = dir.appendingPathComponent("hello.html")
    let exists = fm.fileExists(atPath: created.path)
    if exists { print("=== hello.html ===\n\(try String(contentsOf: created, encoding: .utf8))") }
    #expect(exists, "the agent should have created hello.html on disk — activity: \(activity)")
}
