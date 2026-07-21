import Testing
@testable import SlateCore

@Test func argsCarrySessionAndPermission() {
    let a = ClaudeCode.arguments(sessionId: "sess-123", mode: .acceptEdits, addDir: "/proj")
    #expect(a.contains("--output-format"))
    #expect(a.contains("stream-json"))
    #expect(a.contains("--verbose"))
    #expect(zip(a, a.dropFirst()).contains { $0 == "--resume" && $1 == "sess-123" })
    #expect(zip(a, a.dropFirst()).contains { $0 == "--permission-mode" && $1 == "acceptEdits" })
    #expect(zip(a, a.dropFirst()).contains { $0 == "--add-dir" && $1 == "/proj" })
}

@Test func autopilotUsesClaudePolicyUntilSkipIsExplicit() {
    #expect(ClaudeCode.permissionArgs(.autopilot) == ["--permission-mode", "auto"])
    #expect(ClaudeCode.permissionArgs(.autopilot, skipPermissions: true) == ["--dangerously-skip-permissions"])
    let a = ClaudeCode.arguments(sessionId: nil, mode: .autopilot, addDir: nil,
                                 skipPermissions: true)
    #expect(a.contains("--dangerously-skip-permissions"))
    #expect(!a.contains("--resume"))
    #expect(!a.contains("--add-dir"))
}

@Test func claudeRunsWithoutProjectExtensionsAndKeepsHardDenials() {
    let a = ClaudeCode.arguments(sessionId: nil, mode: .autopilot, addDir: nil,
                                 skipPermissions: true)
    #expect(a.contains("--safe-mode"))
    #expect(a.contains("--disallowedTools"))
    #expect(a.contains("Bash(rm *)"))
    #expect(a.contains("Bash(sudo *)"))
}

@Test func parsesSessionInit() {
    #expect(ClaudeCode.parse(#"{"type":"system","subtype":"init","session_id":"abc-1","tools":[]}"#) == [.sessionStarted("abc-1")])
}

@Test func parsesTextDelta() {
    #expect(ClaudeCode.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}"#) == [.textDelta("Hello")])
}

@Test func parsesThinkingTextAndToolUse() {
    let e = ClaudeCode.parse(#"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Let me check."},{"type":"text","text":"Editing now."},{"type":"tool_use","name":"Edit","input":{"file_path":"src/foo.swift"}}]}}"#)
    #expect(e == [.thinking("Let me check."), .textDelta("Editing now."), .toolUse("⚙ Edit  src/foo.swift")])
}

@Test func parsesToolResult() {
    let e = ClaudeCode.parse(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"line one\nline two"}]}}"#)
    #expect(e == [.toolResult("↳ line one")])
}

@Test func parsesResultWithCostAndErrors() {
    #expect(ClaudeCode.parse(#"{"type":"result","subtype":"success","result":"done","is_error":false,"total_cost_usd":0.0123,"num_turns":4}"#)
            == [.result(text: "done", isError: false, costUSD: 0.0123, turns: 4)])
    #expect(ClaudeCode.parse(#"{"type":"result","subtype":"error_during_execution","is_error":true}"#)
            == [.result(text: nil, isError: true, costUSD: nil, turns: nil)])
}

@Test func modelAndSystemPromptArgs() {
    let a = ClaudeCode.arguments(sessionId: nil, mode: .autopilot, addDir: nil, model: "opus", appendSystemPrompt: "Be terse.")
    #expect(zip(a, a.dropFirst()).contains { $0 == "--model" && $1 == "opus" })
    #expect(zip(a, a.dropFirst()).contains { $0 == "--append-system-prompt" && $1 == "Be terse." })
}

@Test func ignoresJunkAndOtherTypes() {
    #expect(ClaudeCode.parse("").isEmpty)
    #expect(ClaudeCode.parse("not json").isEmpty)
    #expect(ClaudeCode.parse(#"{"type":"user","message":{}}"#).isEmpty)
}
