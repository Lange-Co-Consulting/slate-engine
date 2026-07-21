import Testing
@testable import SlateCore

@Test func exactMatchApplies() throws {
    let original = "line1\nlet x = 1\nline3\n"
    let r = EditApplier.applyToBuffer(original, block: EditBlock(path: "f", search: "let x = 1", replace: "let x = 2"))
    #expect(r?.text == "line1\nlet x = 2\nline3\n")
    #expect(r?.tier == .exact)
}

@Test func whitespaceTolerantMatchApplies() throws {
    let original = "func f() {\n    return 1\n}\n"
    let block = EditBlock(path: "f", search: "func f() { \n return 1\n}", replace: "func f() { return 2 }")
    let r = EditApplier.applyToBuffer(original, block: block)
    #expect(r != nil)
    #expect(r?.tier == .wsNorm)
}

@Test func emptySearchPrepends() throws {
    let r = EditApplier.applyToBuffer("world", block: EditBlock(path: "f", search: "", replace: "hello"))
    #expect(r?.text == "hello\nworld")
}

@Test func noMatchReturnsNil() throws {
    let r = EditApplier.applyToBuffer("abc", block: EditBlock(path: "f", search: "not present", replace: "x"))
    #expect(r == nil)
}

@Test func fuzzyBelowThresholdRejected() throws {
    let r = EditApplier.applyToBuffer("the quick brown fox\n", block: EditBlock(path: "f", search: "zzz qqq www", replace: "X"))
    #expect(r == nil)
}
