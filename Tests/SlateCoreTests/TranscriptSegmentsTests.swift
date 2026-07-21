import Testing
@testable import SlateCore

@Test func groupsConsecutiveToolLines() {
    let text = "Intro.\n`⚙ Edit foo.swift`\n`↳ ok`\n`⚙ Bash ls`\nDone."
    let segs = TranscriptSegments.parse(text)
    #expect(segs.count == 3)
    guard case .prose(let a) = segs[0], case .toolActivity(let lines) = segs[1],
          case .prose(let b) = segs[2] else { Issue.record("wrong shapes"); return }
    #expect(a == "Intro.")
    #expect(lines == [ToolLine(kind: .call, text: "Edit foo.swift"),
                      ToolLine(kind: .result, text: "ok"),
                      ToolLine(kind: .call, text: "Bash ls")])
    #expect(b == "Done.")
}

@Test func keepsCodeFencesIntact() {
    let text = "```swift\nlet x = 1\n```\n`⚙ Read a.txt`"
    let segs = TranscriptSegments.parse(text)
    guard case .code(let lang, let code) = segs[0], case .toolActivity = segs[1]
    else { Issue.record("wrong shapes"); return }
    #expect(lang == "swift" && code == "let x = 1")
}

@Test func userBackticksAreNotToolLines() {
    let segs = TranscriptSegments.parse("Use `swift build` here.")
    #expect(segs.count == 1)
    if case .toolActivity = segs[0] { Issue.record("false positive") }
}

@Test func toolOnlyTextIsOneBlock() {
    let segs = TranscriptSegments.parse("`⚙ Edit a`\n`↳ done`")
    #expect(segs.count == 1)
    guard case .toolActivity(let l) = segs[0] else { Issue.record("not activity"); return }
    #expect(l.count == 2)
}
