import Foundation
import Testing
@testable import SlateSTT

/// Dominant frequency via autocorrelation over a plausible pitch band.
private func dominantHz(_ x: [Float], rate: Double, minHz: Double, maxHz: Double) -> Double {
    let lo = Int(rate / maxHz), hi = min(x.count - 1, Int(rate / minHz))
    var bestLag = lo, bestVal = -Double.greatestFiniteMagnitude
    for lag in lo...hi {
        var s = 0.0
        for i in 0..<(x.count - lag) { s += Double(x[i]) * Double(x[i + lag]) }
        if s > bestVal { bestVal = s; bestLag = lag }
    }
    return rate / Double(bestLag)
}

@Test func resamplePreservesPitchAndLength() {
    let inRate = 24_000.0, outRate = 44_100.0, freq = 200.0
    let n = Int(inRate)
    var input = [Float](repeating: 0, count: n)
    for i in 0..<n { input[i] = Float(sin(2 * Double.pi * freq * Double(i) / inRate)) }

    let out = AudioResample.convert(input, from: inRate, to: outRate)

    // Length scales with the rate ratio (24k → 44.1k ≈ 1.8375×).
    let expectedLen = Double(n) * outRate / inRate
    #expect(abs(Double(out.count) - expectedLen) < expectedLen * 0.02)

    // Pitch is PRESERVED at 200 Hz. A broken (non-resampling) path would read
    // ~367 Hz - the regression that once made the voice chipmunk-robotic.
    let hz = dominantHz(out, rate: outRate, minHz: 100, maxHz: 500)
    #expect(abs(hz - freq) < 15)
}

@Test func resampleIdentityAndEmpty() {
    let x: [Float] = [0.1, -0.2, 0.3, -0.4]
    #expect(AudioResample.convert(x, from: 44_100, to: 44_100) == x)
    #expect(AudioResample.convert([], from: 24_000, to: 44_100).isEmpty)
}
