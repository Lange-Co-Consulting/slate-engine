import Testing
@testable import SlateFlowCore

@MainActor
private func makeSUT(stt: @escaping @Sendable ([Float]) async throws -> String = { _ in "hello world" },
                     insert: @escaping @Sendable (String) async -> Bool = { _ in true })
-> (DictationController, Recorder) {
    let rec = Recorder()
    let c = DictationController(deps: .init(
        startCapture: { rec.log("start") },
        stopCapture:  { rec.log("stop"); return [0.1, 0.2] },
        transcribe:   { s, _ in try await stt(s) },
        cleanup:      { text, _ in text },              // M2 replaces
        insert:       { t in rec.log("insert:\(t)"); return await insert(t) },
        now:          { rec.time }))
    return (c, rec)
}

@MainActor final class Recorder {
    var events: [String] = []; var time = 0.0
    func log(_ s: String) { events.append(s) }
}

@Test @MainActor func pttHappyPath() async {
    let (c, rec) = makeSUT()
    c.fnEdge(.down)
    #expect(c.state == .recording)
    rec.time = 1.0
    c.fnEdge(.up)
    await c.settle()
    #expect(rec.events == ["start", "stop", "insert:hello world"])
    #expect(c.state == .idle)
}

@Test @MainActor func shortTapCancels() async {
    let (c, rec) = makeSUT()
    c.fnEdge(.down)
    rec.time = 0.1                                      // <0.3s hold
    c.fnEdge(.up)
    await c.settle()
    #expect(!rec.events.contains { $0.hasPrefix("insert") })
    #expect(c.state == .idle)
}

@Test @MainActor func doubleTapStartsHandsFree() async {
    let (c, rec) = makeSUT()
    c.fnEdge(.down); rec.time = 0.1; c.fnEdge(.up)      // tap 1 (cancels its own start)
    rec.time = 0.3; c.fnEdge(.down); rec.time = 0.4; c.fnEdge(.up) // tap 2 within window
    #expect(c.state == .recording)
    #expect(c.handsFree)
    rec.time = 5.0
    c.fnEdge(.down); rec.time = 5.1; c.fnEdge(.up)      // any tap stops hands-free
    await c.settle()
    #expect(rec.events.contains("insert:hello world"))
    #expect(c.state == .idle)
    #expect(!c.handsFree)
}

@Test @MainActor func escCancelsRecording() async {
    let (c, rec) = makeSUT()
    c.fnEdge(.down)
    #expect(c.state == .recording)
    c.cancel()
    await c.settle()
    #expect(c.state == .idle)
    #expect(!rec.events.contains { $0.hasPrefix("insert") })
}

@Test @MainActor func insertFailureSurfacesError() async {
    let (c, rec) = makeSUT(insert: { _ in false })
    c.fnEdge(.down)
    rec.time = 1.0
    c.fnEdge(.up)
    await c.settle()
    #expect(c.lastError != nil)
    #expect(c.state == .idle)
}

@Test @MainActor func emptyTranscriptNoInsert() async {
    let (c, rec) = makeSUT(stt: { _ in "  " })
    c.fnEdge(.down); rec.time = 1.0; c.fnEdge(.up)
    await c.settle()
    #expect(!rec.events.contains { $0.hasPrefix("insert") })
    #expect(c.state == .idle)
}

@Test @MainActor func rawModeSkipsCleanup() async {
    // cleanup dep uppercases; smartFormatting=false must bypass it.
    let rec = Recorder()
    let c = DictationController(deps: .init(
        startCapture: { rec.log("start") },
        stopCapture:  { rec.log("stop"); return [0.1] },
        transcribe:   { _, _ in "hello" },
        cleanup:      { text, _ in text.uppercased() },
        insert:       { t in rec.log("insert:\(t)"); return true },
        now:          { rec.time }))
    c.smartFormatting = false
    c.fnEdge(.down); rec.time = 1.0; c.fnEdge(.up)
    await c.settle()
    #expect(rec.events.contains("insert:hello"))        // NOT "HELLO"
}

@Test @MainActor func toggleManualStartsAndFinishes() async {
    let (c, rec) = makeSUT()
    c.toggleManual()
    #expect(c.state == .recording && c.handsFree)       // click 1: recording, no cap-by-release
    rec.time = 4.0
    c.toggleManual()                                    // click 2: finalize
    await c.settle()
    #expect(rec.events.contains("insert:hello world"))
    #expect(c.state == .idle && !c.handsFree)
}

@Test @MainActor func handsFreeCapAutoFinalizes() async {
    let (c, rec) = makeSUT()
    c.fnEdge(.down); rec.time = 0.1; c.fnEdge(.up)
    rec.time = 0.3; c.fnEdge(.down); rec.time = 0.4; c.fnEdge(.up) // hands-free on
    #expect(c.handsFree)
    rec.time = 0.4 + 20 * 60 + 1                        // past the 20-min cap
    c.tick()
    await c.settle()
    #expect(rec.events.contains("insert:hello world"))
    #expect(c.state == .idle && !c.handsFree)
}
