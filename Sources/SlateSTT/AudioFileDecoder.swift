import AudioToolbox
import Foundation

public enum AudioFileDecodeError: Error, LocalizedError, Sendable {
    case unsupportedFile
    case conversionFailed(OSStatus)
    case tooLarge
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "This audio or video file has no supported audio track."
        case .conversionFailed(let status): return "Audio conversion failed (\(status))."
        case .tooLarge: return "This file is larger than Slate's 4 GB safe import limit."
        case .tooLong: return "This file is longer than Slate's 30-minute safe import limit. Split it into smaller files first."
        }
    }
}

/// Decodes any Core Audio-readable audio track (WAV, MP3, M4A, MP4/MOV audio,
/// AIFF and others) into Parakeet's 16 kHz mono Float32 input, fully locally.
public enum AudioFileDecoder {
    public static let sampleRate = 16_000.0
    public static let maxDurationSeconds = 30 * 60.0
    public static let maxSamples = Int(sampleRate * maxDurationSeconds)
    public static let maxInputBytes = 4 * 1_024 * 1_024 * 1_024

    public static func decode(url: URL) throws -> [Float] {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw AudioFileDecodeError.unsupportedFile
        }
        guard (values?.fileSize ?? 0) <= maxInputBytes else { throw AudioFileDecodeError.tooLarge }
        var file: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &file) == noErr, let file else {
            throw AudioFileDecodeError.unsupportedFile
        }
        defer { ExtAudioFileDispose(file) }

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let setStatus = withUnsafePointer(to: &clientFormat) {
            ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size), $0)
        }
        guard setStatus == noErr else { throw AudioFileDecodeError.conversionFailed(setStatus) }

        let chunkFrames = 16_384
        var chunk = [Float](repeating: 0, count: chunkFrames)
        var samples: [Float] = []
        while true {
            var frames = UInt32(chunkFrames)
            let status = chunk.withUnsafeMutableBytes { rawBuffer -> OSStatus in
                let audioBuffer = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rawBuffer.count),
                    mData: rawBuffer.baseAddress
                )
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
                return ExtAudioFileRead(file, &frames, &list)
            }
            guard status == noErr else { throw AudioFileDecodeError.conversionFailed(status) }
            if frames == 0 { break }
            guard samples.count <= maxSamples - Int(frames) else { throw AudioFileDecodeError.tooLong }
            samples.append(contentsOf: chunk.prefix(Int(frames)))
        }
        guard !samples.isEmpty else { throw AudioFileDecodeError.unsupportedFile }
        return samples
    }
}
