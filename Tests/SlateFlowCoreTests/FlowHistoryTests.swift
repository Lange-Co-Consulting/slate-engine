import Testing
import Foundation
@testable import SlateFlowCore

@Test func wavRoundTripsSamples() {
    let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
    let wav = FlowHistory.wavData(samples)
    #expect(wav.count == 44 + samples.count * 2)          // header + 16-bit PCM
    // Decode the body back the same way parkedRecording() does.
    let body = wav.dropFirst(44)
    var decoded = [Float]()
    var i = body.startIndex
    while i + 1 < body.endIndex {
        let lo = UInt16(body[i]), hi = UInt16(body[i + 1])
        decoded.append(Float(Int16(bitPattern: lo | (hi << 8))) / 32767)
        i += 2
    }
    #expect(decoded.count == samples.count)
    for (a, b) in zip(decoded, samples) { #expect(abs(a - b) < 0.001) }
}

@Test func historyEntryRoundTrips() throws {
    let e = FlowHistoryEntry(raw: "hallo ähm welt", polished: "Hallo Welt.", durationSec: 3.2)
    let data = try JSONEncoder().encode(e)
    let back = try JSONDecoder().decode(FlowHistoryEntry.self, from: data)
    #expect(back == e)
}
