import Testing
@testable import SlateFlowCore

@Test func emitsCleanEdges() {
    var d = FnDebouncer()
    #expect(d.feed(fnDown: true,  at: 0.000) == .down)
    #expect(d.feed(fnDown: true,  at: 0.050) == nil)     // repeat, no edge
    #expect(d.feed(fnDown: false, at: 0.500) == .up)
}

@Test func dropsFlicker() {
    var d = FnDebouncer()
    #expect(d.feed(fnDown: true,  at: 0.000) == .down)
    #expect(d.feed(fnDown: false, at: 0.020) == nil)     // <40ms flicker ignored
    #expect(d.feed(fnDown: true,  at: 0.030) == nil)     // back down — still logically down
    #expect(d.feed(fnDown: false, at: 0.300) == .up)
}

@Test func flickerThatSettlesUpStillEmitsUp() {
    var d = FnDebouncer()
    #expect(d.feed(fnDown: true,  at: 0.000) == .down)
    #expect(d.feed(fnDown: false, at: 0.010) == nil)     // flicker up
    // No further reports; a later genuine up must still emit.
    #expect(d.feed(fnDown: false, at: 0.200) == .up)
}
