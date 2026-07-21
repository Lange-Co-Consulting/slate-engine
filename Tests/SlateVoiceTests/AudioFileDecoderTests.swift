import AVFAudio
import XCTest
@testable import SlateSTT

final class AudioFileDecoderTests: XCTestCase {
    func testDecodesAndResamplesStereoWavToSixteenKilohertzMono() throws {
        let url = URL.temporaryDirectory.appendingPathComponent("slate-audio-decoder-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let frameCount = 44_100
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for index in 0..<frameCount {
                samples[index] = sin(Float(index) * 2 * .pi * 440 / 44_100) * 0.2
            }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let decoded = try AudioFileDecoder.decode(url: url)
        XCTAssertEqual(decoded.count, 16_000, accuracy: 4)
        let peak = decoded.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, 0.3)
    }
}
