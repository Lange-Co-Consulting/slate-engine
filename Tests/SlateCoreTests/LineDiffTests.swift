import Testing
@testable import SlateCore

@Test func diffReplacesMiddleLine() {
    let d = LineDiff.compute(old: "a\nb\nc", new: "a\nx\nc")
    #expect(d == [.context("a"), .removed("b"), .added("x"), .context("c")])
}

@Test func diffPureAddition() {
    let d = LineDiff.compute(old: "a\nb", new: "a\nb\nc")
    #expect(d == [.context("a"), .context("b"), .added("c")])
}

@Test func diffFromEmptyIsAllAdded() {
    let d = LineDiff.compute(old: "", new: "x\ny")
    #expect(d == [.added("x"), .added("y")])
}

@Test func diffStats() {
    let s = LineDiff.stats(old: "a\nb\nc", new: "a\nx\ny\nc")
    #expect(s.added == 2)
    #expect(s.removed == 1)
}
