import Testing
@testable import SlateFlowCore

@Test func restoresWhenUnchanged() {
    let g = ClipboardGuard(savedChangeCount: 5, ourChangeCount: 6)
    #expect(g.shouldRestore(currentChangeCount: 6))          // our write is still newest
}

@Test func skipsRestoreWhenSomeoneElseWrote() {
    let g = ClipboardGuard(savedChangeCount: 5, ourChangeCount: 6)
    #expect(!g.shouldRestore(currentChangeCount: 8))         // user copied meanwhile
}
