import Foundation
import Testing
@testable import SlateCore

// MARK: - ProjectMemory

@Test func projectMemoryAddDedupesAndCaps() {
    var m = ProjectMemory()
    #expect(m.add("Build with swift build") == true)
    #expect(m.add("build with swift build") == false)          // normalized dup
    #expect(m.add("swift build") == false)                     // containment dup
    #expect(m.add("Tests run with swift test") == true)
    #expect(m.facts.count == 2)

    // 3-digit ids so none is a substring of another (the containment-dedupe is real).
    for i in 100..<160 { m.add("fact number \(i)") }
    #expect(m.facts.count == ProjectMemory.cap)                // oldest fall off
    #expect(m.facts.last?.text == "fact number 159")
}

@Test func projectMemorySanitize() {
    #expect(ProjectMemory.sanitize("  - swift build \n more ") == "swift build")
    #expect(ProjectMemory.sanitize("none") == nil)
    #expect(ProjectMemory.sanitize("   ") == nil)
    #expect(ProjectMemory.sanitize(String(repeating: "x", count: 300)) == nil)
    #expect(ProjectMemory.sanitize("\"Uses SwiftPM, no Xcode\"") == "Uses SwiftPM, no Xcode")
}

@Test func projectMemoryAugment() {
    var m = ProjectMemory()
    m.add("Build: swift build")
    let block = ProjectMemory.augment(systemPrompt: "BASE", with: m, canRemember: true)
    #expect(block.contains("BASE"))
    #expect(block.contains("Build: swift build"))
    #expect(block.contains("remember_project_fact"))

    // No facts + can't remember → base unchanged.
    #expect(ProjectMemory.augment(systemPrompt: "BASE", with: nil, canRemember: false) == "BASE")
    // Can remember but no facts yet → still teaches the tool.
    #expect(ProjectMemory.augment(systemPrompt: "BASE", with: nil, canRemember: true).contains("remember_project_fact"))
}

// MARK: - DevServerURL

@Test func devServerURLAcceptsLocalTargets() {
    #expect(DevServerURL.parse("3000")?.absoluteString == "http://localhost:3000")
    #expect(DevServerURL.parse("localhost:5173")?.absoluteString == "http://localhost:5173")
    #expect(DevServerURL.parse("http://localhost:3000")?.absoluteString == "http://localhost:3000")
    #expect(DevServerURL.parse("127.0.0.1:8080/app")?.host == "127.0.0.1")
    #expect(DevServerURL.parse("127.0.0.1:8080/app")?.path == "/app")
    #expect(DevServerURL.parse("https://localhost:443")?.scheme == "https")
    #expect(DevServerURL.parse("http://[::1]:3000")?.host == "::1")
}

@Test func devServerURLRejectsNonLocal() {
    #expect(DevServerURL.parse("") == nil)
    #expect(DevServerURL.parse("0") == nil)                    // invalid port
    #expect(DevServerURL.parse("example.com") == nil)
    #expect(DevServerURL.parse("http://evil.com:3000") == nil)
    #expect(DevServerURL.parse("https://api.example.com") == nil)
    #expect(DevServerURL.parse("file:///etc/passwd") == nil)
    #expect(DevServerURL.parse("ftp://localhost:21") == nil)   // unsupported scheme
}
