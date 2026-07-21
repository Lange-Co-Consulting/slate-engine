import Testing
import Foundation
@testable import SlateCore

// MARK: ProjectRules

@Test func projectRulesFindsAndAugments() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-rules-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    try "Use tabs. Prefer small files.".write(to: dir.appendingPathComponent("SLATE.md"), atomically: true, encoding: .utf8)

    let found = ProjectRules.find(in: dir)
    #expect(found?.name == "SLATE.md")
    let prompt = ProjectRules.augment(systemPrompt: "BASE", with: found)
    #expect(prompt.contains("Trusted project conventions"))
    #expect(prompt.contains("Use tabs"))
    #expect(prompt.hasSuffix("BASE"))
    #expect(ProjectRules.augment(systemPrompt: "BASE", with: nil) == "BASE")

    let firstDigest = found?.digest
    try "Different rules".write(to: dir.appendingPathComponent("SLATE.md"), atomically: true, encoding: .utf8)
    #expect(ProjectRules.find(in: dir)?.digest != firstDigest)
}

@Test func projectRulesRejectsSymlinkEscapingWorkspace() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-rules-root-\(UUID().uuidString)")
    let outside = fm.temporaryDirectory.appendingPathComponent("slate-rules-secret-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir); try? fm.removeItem(at: outside) }
    try "secret".write(to: outside, atomically: true, encoding: .utf8)
    try fm.createSymbolicLink(at: dir.appendingPathComponent("SLATE.md"), withDestinationURL: outside)
    #expect(ProjectRules.find(in: dir) == nil)
}

// MARK: SlashCommands

@Test func slashExpandsBuiltins() {
    #expect(SlashCommands.expand("/explain recursion").contains("recursion"))
    #expect(SlashCommands.expand("/explain recursion").contains("Explain"))
    #expect(SlashCommands.expand("just text") == "just text")      // not a command
    #expect(SlashCommands.expand("/unknown x") == "/unknown x")    // unknown command untouched
}

@Test func slashMatchesPrefix() {
    #expect(SlashCommands.matches("").count == SlashCommands.builtins.count)
    #expect(SlashCommands.matches("te").map(\.name) == ["test"])
    let custom = [SlashCommand(name: "ship", title: "Ship", summary: "", template: "ship it")]
    #expect(SlashCommands.matches("sh", custom: custom).map(\.name).contains("ship"))
}

@Test func workflowCommandsExpandForAnyModel() {
    // The Claude Code-style workflow commands are present and expand their
    // structured template with the user's argument substituted in — the whole
    // mechanism is prompt injection, so it is identical for local and cloud models.
    let names = Set(SlashCommands.builtins.map(\.name))
    for command in ["research", "brainstorm", "plan", "goal", "debug", "spec", "optimize", "document"] {
        #expect(names.contains(command))
    }
    let goal = SlashCommands.expand("/goal ship the parser")
    #expect(goal.contains("ship the parser"))
    #expect(goal.contains("done when"))                 // the goal-condition instruction survives
    let research = SlashCommands.expand("/research vector databases")
    #expect(research.contains("vector databases"))
    #expect(research.contains("Bottom line"))
    // The {input} placeholder is always substituted, never left literal.
    #expect(!SlashCommands.expand("/brainstorm a CLI tool").contains("{input}"))
}

// MARK: TokenEstimate

@Test func tokenEstimateScalesAndFormats() {
    #expect(TokenEstimate.tokens("") == 0)
    #expect(TokenEstimate.tokens(String(repeating: "x", count: 360)) == 100)
    #expect(TokenEstimate.tokens([ChatMessage(role: .user, content: "hi")]) >= 4)
    #expect(TokenEstimate.short(1500) == "1.5k")
    #expect(TokenEstimate.short(850) == "850")
}

// MARK: ClaudeCodeImport

@Test func claudeCodeEncodesPath() {
    let u = URL(fileURLWithPath: "/Users/x/Proj")
    #expect(ClaudeCodeImport.encode(u) == "-Users-x-Proj")
}

@Test func claudeCodeParsesSessionJSONL() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("slate-cc-\(UUID().uuidString)")
    let folder = URL(fileURLWithPath: "/Users/x/MyProj")
    let dir = base.appendingPathComponent(ClaudeCodeImport.encode(folder), isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    // String content + array-of-blocks content + a tool line that must be skipped.
    let lines = [
        #"{"type":"user","message":{"role":"user","content":"add a login page"}}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Sure, creating it."},{"type":"tool_use","name":"edit","input":{}}]}}"#,
        #"{"type":"system","content":"noise"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
    ]
    try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

    let sessions = ClaudeCodeImport.sessions(forFolder: folder, projectsDir: base)
    #expect(sessions.count == 1)
    #expect(sessions[0].title.contains("add a login page"))

    let msgs = ClaudeCodeImport.messages(from: sessions[0].fileURL)
    #expect(msgs.count == 2)                       // 2 text turns; tool/system skipped
    #expect(msgs[0].role == .user)
    #expect(msgs[0].content == "add a login page")
    #expect(msgs[1].content == "Sure, creating it.")
}

@Test func claudeCodeRecentTailRespectsBudget() {
    let msgs = (0..<10).map { _ in ChatMessage(role: .user, content: String(repeating: "x", count: 100)) }
    let tail = ClaudeCodeImport.recentTail(msgs, budget: 250)
    #expect(tail.count >= 1 && tail.count < msgs.count)
}
