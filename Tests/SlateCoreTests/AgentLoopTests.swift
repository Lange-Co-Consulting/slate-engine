import Testing
import Foundation
@testable import SlateCore

/// Engine that returns a different scripted response per call (turn).
private actor ScriptedEngine: LLMEngine {
    private var turns: [String]
    private var i = 0
    init(turns: [String]) { self.turns = turns }
    func generate(messages: [ChatMessage], grammar: GrammarSpec?, options: GenOptions) async -> AsyncThrowingStream<String, Error> {
        let text = i < turns.count ? turns[i] : "done"
        i += 1
        return AsyncThrowingStream { c in c.yield(text); c.finish() }
    }
}

@Test func runsToolThenReturnsFinalAnswer() async throws {
    let engine = ScriptedEngine(turns: [
        #"<tool_call>{"name":"echo","arguments":{"text":"hi"}}</tool_call>"#,
        #"<tool_call>{"name":"finish","arguments":{"message":"The tool said hi."}}</tool_call>"#,
    ])
    let registry = ToolRegistry(tools: [
        RegisteredTool(spec: ToolSpec(name: "echo", description: "d",
                                      parameters: [.init(name: "text", description: "t", required: true)])) { args in
            "echoed:\(args["text"] ?? "")"
        }
    ])
    let loop = AgentLoop(engine: engine, registry: registry)
    var session = ChatSession(system: "sys")
    session.append(ChatMessage(role: .user, content: "say hi"))

    var finalAnswer = ""
    var toolNames: [String] = []
    for try await event in loop.run(session: session) {
        switch event {
        case .toolCall(let name, _): toolNames.append(name)
        case .finalAnswer(let text): finalAnswer = text
        default: break
        }
    }
    #expect(toolNames == ["echo"])
    #expect(finalAnswer == "The tool said hi.")
}

@Test func stopsAtMaxIterations() async throws {
    let engine = ScriptedEngine(turns: Array(repeating:
        #"<tool_call>{"name":"noop","arguments":{"x":"1"}}</tool_call>"#, count: 50))
    let registry = ToolRegistry(tools: [
        RegisteredTool(spec: ToolSpec(name: "noop", description: "d",
                                      parameters: [.init(name: "x", description: "x", required: true)])) { _ in "ok" }
    ])
    let loop = AgentLoop(engine: engine, registry: registry, maxIterations: 3)
    var session = ChatSession()
    session.append(ChatMessage(role: .user, content: "loop"))
    var calls = 0
    for try await event in loop.run(session: session) {
        if case .toolCall = event { calls += 1 }
    }
    #expect(calls == 3)
}
