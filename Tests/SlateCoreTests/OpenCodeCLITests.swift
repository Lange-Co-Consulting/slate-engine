import Foundation
import Testing
@testable import SlateCore

@Test func openCodeArgumentsCarryModelSessionAndSafetyLatch() {
    let normal = OpenCodeCLI.arguments(model: "openai/gpt-5", sessionID: "ses_1",
                                       directory: "/project", skipPermissions: false)
    #expect(normal.starts(with: ["run", "--pure", "--format", "json"]))
    #expect(zip(normal, normal.dropFirst()).contains { $0 == "--model" && $1 == "openai/gpt-5" })
    #expect(zip(normal, normal.dropFirst()).contains { $0 == "--session" && $1 == "ses_1" })
    #expect(!normal.contains("--dangerously-skip-permissions"))

    let bypass = OpenCodeCLI.arguments(model: "openai/gpt-5", sessionID: nil,
                                       directory: "/project", skipPermissions: true)
    #expect(bypass.contains("--dangerously-skip-permissions"))
}

@Test func parsesOpenCodeJSONEvents() {
    let text = OpenCodeCLI.parse(#"{"type":"text","sessionID":"ses_1","part":{"type":"text","text":"OK"}}"#)
    #expect(text == [.sessionStarted("ses_1"), .text("OK")])

    let finish = OpenCodeCLI.parse(#"{"type":"step_finish","sessionID":"ses_1","part":{"type":"step-finish","tokens":{"total":42},"cost":0.01}}"#)
    #expect(finish == [.sessionStarted("ses_1"), .finished(totalTokens: 42, cost: 0.01)])
}

@Test func parsesAndDeduplicatesOpenCodeModels() {
    #expect(OpenCodeCLI.models(from: "openai/gpt-5\nanthropic/claude\nopenai/gpt-5\nnoise line\n")
            == ["openai/gpt-5", "anthropic/claude"])
}

@Test func openCodePermissionsFollowSlateModeAndKeepHardDenials() throws {
    func permissions(_ mode: PermissionMode) throws -> [String: Any] {
        let data = try #require(OpenCodeCLI.permissionJSON(mode).data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    let ask = try permissions(.ask)
    #expect(ask["edit"] as? String == "ask")
    #expect((ask["bash"] as? [String: String])?["*"] == "ask")

    let edits = try permissions(.acceptEdits)
    #expect(edits["edit"] as? String == "allow")
    #expect((edits["bash"] as? [String: String])?["git status"] == nil)

    let auto = try permissions(.autopilot)
    let bash = try #require(auto["bash"] as? [String: String])
    #expect(bash["git status"] == "allow")
    #expect(bash["rm *"] == "deny")
    #expect(bash["sudo *"] == "deny")
    #expect(auto["external_directory"] as? String == "deny")
    #expect(auto["webfetch"] as? String == "deny")
}
