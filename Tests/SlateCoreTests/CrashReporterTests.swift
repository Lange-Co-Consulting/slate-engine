import Foundation
import Testing
@testable import SlateCore

@Suite struct CrashReporterTests {
    @Test func stripsHomePaths() {
        let s = CrashReporter.sanitize("crash at /Users/LangeUndCo/Projects/Slate/x.swift line 5",
                                       username: "LangeUndCo", homeDir: "/Users/LangeUndCo")
        #expect(s.contains("/Users/<user>/Projects/Slate/x.swift"))
        #expect(!s.contains("LangeUndCo"))
    }

    @Test func stripsAnyUsersPath() {
        let s = CrashReporter.sanitize("path /Users/someoneelse/Library/foo",
                                       username: "me", homeDir: "/Users/me")
        #expect(s.contains("/Users/<user>/Library/foo"))
        #expect(!s.contains("someoneelse"))
    }

    @Test func stripsStandaloneUsername() {
        let s = CrashReporter.sanitize("account: LangeUndCo (admin)", username: "LangeUndCo", homeDir: "/Users/LangeUndCo")
        #expect(!s.contains("LangeUndCo"))
        #expect(s.contains("<user>"))
    }

    @Test func leavesTechnicalContentIntact() {
        let s = CrashReporter.sanitize("Thread 0 Crashed: EXC_BAD_ACCESS (SIGSEGV) in libsystem",
                                       username: "me", homeDir: "/Users/me")
        #expect(s.contains("EXC_BAD_ACCESS"))
        #expect(s.contains("SIGSEGV"))
    }

    @Test func emptyUsernameIsSafe() {
        let s = CrashReporter.sanitize("/Users/x/y", username: "", homeDir: "")
        #expect(s.contains("/Users/<user>/y"))
    }

    @Test func stripsJSONEscapedUsersPath() {
        let s = CrashReporter.sanitize(#"procPath \/Users\/alice\/Slate.app"#, username: "alice", homeDir: "/Users/alice")
        #expect(!s.contains("alice"))
        #expect(s.contains("/Users/<user>"))
    }

    @Test func usernameReplaceIsWholeWordOnly() {
        let s = CrashReporter.sanitize("user sam ran benchmark sample", username: "sam", homeDir: "/Users/sam")
        #expect(s.contains("benchmark"))   // not shredded
        #expect(s.contains("sample"))
        #expect(s.contains("<user>"))      // standalone "sam" replaced
        #expect(!s.contains(" sam "))
    }

    /// The headline privacy guarantee: a real .ips carries stable device
    /// fingerprints and paths; the anonymous report must NOT.
    @Test func reportExcludesDeviceFingerprintsAndPaths() {
        let raw = """
        {"app_version":"0.1.0","os_version":"macOS 26.5","bug_type":"309","timestamp":"2026-07-11 00:00:00.00 +0000"}
        {"crashReporterKey":"13E03018-38ED-2F10-15EF-C76040135D9D","deviceIdentifierForVendor":"10580A48-764E-57B1","bootSessionUUID":"AAA","sleepWakeUUID":"BBB","exception":{"signal":"SIGABRT","type":"EXC_CRASH"},"termination":{"namespace":"SIGNAL"},"usedImages":[{"name":"Slate","path":"/Users/langeundco/Applications/Slate.app/Contents/MacOS/Slate"}],"threads":[{"triggered":true,"frames":[{"imageIndex":0,"symbol":"main"}]}]}
        """
        let out = CrashReporter.report(fromRawIPS: raw, username: "langeundco", homeDir: "/Users/langeundco")
        #expect(!out.contains("13E03018"))                 // crashReporterKey gone
        #expect(!out.contains("10580A48"))                 // deviceIdentifierForVendor gone
        #expect(!out.contains("bootSessionUUID"))
        #expect(!out.contains("/Users/langeundco"))        // path gone
        #expect(out.contains("SIGABRT"))                   // safe signal kept
        #expect(out.contains("0.1.0"))                     // app version kept
        #expect(out.contains("main"))                      // frame symbol kept
    }
}
