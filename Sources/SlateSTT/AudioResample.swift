import AVFoundation
import Foundation

/// Correct sample-rate conversion for mono Float32 audio (neural TTS models emit
/// 24 kHz; Slate's playback engines run at 44.1 kHz). Uses AVAudioConverter's
/// BLOCK-BASED API - the only variant that actually performs rate conversion. The
/// one-shot `convert(to:from:)` does NOT resample and plays audio ~1.84x too fast
/// (high-pitched, robotic) - that bug shipped once; the unit test pins it dead.
public enum AudioResample {
    /// Feeds the single input buffer to the converter exactly once. Confined to the
    /// synchronous convert() call, so the unchecked Sendable is safe.
    private final class Feed: @unchecked Sendable {
        var done = false
        let buffer: AVAudioPCMBuffer
        init(_ b: AVAudioPCMBuffer) { buffer = b }
    }

    public static func convert(_ input: [Float], from inRate: Double, to outRate: Double) -> [Float] {
        guard !input.isEmpty, inRate > 0, outRate > 0 else { return input }
        if inRate == outRate { return input }
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inRate, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(input.count))
        else { return input }

        inBuffer.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { src in
            inBuffer.floatChannelData!.pointee.update(from: src.baseAddress!, count: input.count)
        }

        let capacity = AVAudioFrameCount((Double(input.count) * outRate / inRate).rounded(.up)) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return input }

        let feed = Feed(inBuffer)
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if feed.done { outStatus.pointee = .endOfStream; return nil }
            feed.done = true
            outStatus.pointee = .haveData
            return feed.buffer
        }
        guard status != .error, error == nil,
              outBuffer.frameLength > 0, let ch = outBuffer.floatChannelData?.pointee
        else { return input }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuffer.frameLength)))
    }
}
