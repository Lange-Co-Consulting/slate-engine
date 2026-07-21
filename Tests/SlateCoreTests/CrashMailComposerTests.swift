import Testing
import Foundation
@testable import SlateCore

@Test func mailtoEncodesRecipientSubjectBody() {
    let report = CrashReport(id: "Slate-1.ips", date: .distantPast, appVersion: "1.2",
                             osVersion: "macOS 26", summary: "SIGABRT", body: "line one\nline two")
    let url = CrashMailComposer.mailtoURL(report, to: "dev@example.com")!
    #expect(url.scheme == "mailto")
    #expect(url.absoluteString.contains("dev@example.com"))
    #expect(url.absoluteString.contains("subject="))
    #expect(url.absoluteString.contains("1.2"))          // version in subject
    #expect(!url.absoluteString.contains("\n"))          // newlines are percent-encoded
}

@Test func mailtoTruncatesOversizedBody() {
    let big = String(repeating: "x", count: 20_000)
    let report = CrashReport(id: "a.ips", date: .distantPast, appVersion: "1", osVersion: "26",
                             summary: "s", body: big)
    let url = CrashMailComposer.mailtoURL(report, to: "d@e.com")!
    #expect(url.absoluteString.count <= CrashMailComposer.maxURLLength)
    #expect(url.absoluteString.contains("truncated"))
}
