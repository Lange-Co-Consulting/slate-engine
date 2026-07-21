import Testing
@testable import SlateCore

@Test func newSessionsFailClosed() {
    #expect(PermissionMode.recommendedDefault == .ask)
}

@Test func autoUsesRiskUnlessSkipIsExplicit() {
    #expect(PermissionPolicy.requiresConfirmation(mode: .autopilot, kind: .fileWrite,
                                                   risk: .safe) == false)
    #expect(PermissionPolicy.requiresConfirmation(mode: .autopilot, kind: .shellCommand,
                                                   risk: .sensitive) == true)
    #expect(PermissionPolicy.requiresConfirmation(mode: .autopilot, kind: .shellCommand,
                                                   risk: .destructive,
                                                   skipPermissions: true) == false)
}

@Test func acceptEditsAllowsEditsAsksCommands() {
    #expect(PermissionPolicy.requiresConfirmation(mode: .acceptEdits, kind: .fileWrite) == false)
    #expect(PermissionPolicy.requiresConfirmation(mode: .acceptEdits, kind: .shellCommand) == true)
    #expect(PermissionPolicy.requiresConfirmation(mode: .acceptEdits, kind: .fileWrite,
                                                   risk: .destructive) == true)
}

@Test func skipDoesNotWeakenAskMode() {
    #expect(PermissionPolicy.requiresConfirmation(mode: .ask, kind: .fileWrite,
                                                   risk: .safe,
                                                   skipPermissions: true) == true)
}

@Test func fileChangeRiskFlagsSensitiveAndDeletionHeavyChanges() {
    #expect(FileChangeRisk.classify(path: "Sources/App.swift", old: nil, new: "new") == .safe)
    #expect(FileChangeRisk.classify(path: ".env", old: nil, new: "TOKEN=x") == .sensitive)
    #expect(FileChangeRisk.classify(path: "Sources/App.swift", old: "important\n", new: "") == .destructive)
    #expect(FileChangeRisk.classify(path: "Sources/App.swift", old: "old", new: "new",
                                    wholeFileReplacement: true) == .sensitive)
}

@Test func askConfirmsEverything() {
    #expect(PermissionPolicy.requiresConfirmation(mode: .ask, kind: .fileWrite) == true)
    #expect(PermissionPolicy.requiresConfirmation(mode: .ask, kind: .shellCommand) == true)
}
