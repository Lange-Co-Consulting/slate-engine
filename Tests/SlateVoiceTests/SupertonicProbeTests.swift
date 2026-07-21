import XCTest
import AVFAudio
@testable import SlateSTT

/// GO/NO-GO gate from the voice spec: synthesize German + English probes and
/// write WAVs to /tmp/slate-voice-probe for the operator to judge. Gated
/// behind SLATE_TTS_PROBE=1 (first run downloads ~100 MB — one-time, like
/// Parakeet; fully offline afterwards).
final class SupertonicProbeTests: XCTestCase {
    func testGermanAndEnglishProbes() async throws {
        guard ProcessInfo.processInfo.environment["SLATE_TTS_PROBE"] == "1" else {
            throw XCTSkip("set SLATE_TTS_PROBE=1 to run (downloads models once)")
        }
        let tts = SupertonicTTS()
        try await tts.prepare(voices: ["F1", "M1"])

        let dir = URL(fileURLWithPath: "/tmp/slate-voice-probe")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let probes: [(lang: String, voice: String, text: String)] = [
            ("de", "F1", "Hallo! Ich bin Slate. Ich laufe komplett offline auf deinem Mac — auch meine Stimme kommt von der Neural Engine."),
            ("de", "M1", "Kurzer Technik-Check: Umlaute wie schön, größer und über, dazu ein Datum — der zehnte Juli zweitausendsechsundzwanzig."),
            ("en", "F1", "Hey! This is Slate's English voice. Everything you hear is generated locally, nothing leaves your Mac."),
        ]
        for p in probes {
            let samples = try await tts.synthesize(p.text, language: p.lang, voice: p.voice)
            XCTAssertGreaterThan(samples.count, 22_050, "\(p.lang)/\(p.voice): under 0.5 s of audio")
            let rms = (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
            XCTAssertGreaterThan(rms, 0.005, "\(p.lang)/\(p.voice): near-silence — synthesis broken")
            try write(samples, to: dir.appendingPathComponent("probe-\(p.lang)-\(p.voice).wav"))
        }
    }

    private func write(_ samples: [Float], to url: URL) throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))!
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
        try file.write(from: buf)
    }
}
