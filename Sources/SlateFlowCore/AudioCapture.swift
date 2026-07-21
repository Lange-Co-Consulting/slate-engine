@preconcurrency import AVFoundation

/// Mic capture for dictation. Two hard-won rules live here:
///  1. NEVER `prepare()` an empty graph at init - AVAudioEngineGraph raises an
///     NSException and aborts the app at launch. prepare() only after installTap.
///  2. The tap callback MUST be `@Sendable` (explicitly non-isolated): this
///     class is @MainActor, and a closure formed here inherits that isolation  - 
///     but AVFAudio invokes the tap on its realtime queue, and Swift 6's dynamic
///     isolation check then traps (dispatch_assert_queue_fail → SIGTRAP on the
///     first buffer). All audio-thread state sits in TapBox; results hop to the
///     main actor via Task.
/// The engine only RUNS while recording - no orange mic dot at idle. The tap
/// converts whatever the input device delivers to 16 kHz mono Float32 (what
/// Parakeet eats) and reports an RMS level for the Flow Bar waveform.
@MainActor public final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    public private(set) var level: Float = 0
    public var onLevel: ((Float) -> Void)?

    public init() {}

    public func start() {
        samples.removeAll()
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        // sampleRate 0 = no usable input (e.g. mic permission not granted yet).
        guard inFmt.sampleRate > 0,
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false),
              let box = TapBox(from: inFmt, to: outFmt) else { return }

        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { @Sendable [weak self] buf, _ in
            // Audio thread: convert + measure here, touch NO MainActor state.
            guard let chunk = box.convert(buf) else { return }
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.samples.append(contentsOf: chunk)
                self.level = min(1, rms * 12)
                self.onLevel?(self.level)
            }
        }
        engine.prepare()                    // safe HERE: the graph now has a tap
        try? engine.start()
    }

    /// Stops the engine and returns everything captured since start().
    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
        defer { samples.removeAll() }
        return samples
    }
}

/// Conversion state confined to the tap's audio queue. @unchecked Sendable is
/// sound because AVFAudio serializes tap callbacks - only that one queue ever
/// touches the converter.
private final class TapBox: @unchecked Sendable {
    private final class FeedState: @unchecked Sendable { var didFeed = false }
    private let converter: AVAudioConverter
    private let outFmt: AVAudioFormat
    private let ratio: Double

    init?(from inFmt: AVAudioFormat, to outFmt: AVAudioFormat) {
        guard let c = AVAudioConverter(from: inFmt, to: outFmt) else { return nil }
        converter = c
        self.outFmt = outFmt
        ratio = outFmt.sampleRate / inFmt.sampleRate
    }

    /// One input buffer → 16 kHz mono Float32 chunk (nil on conversion failure).
    func convert(_ buf: AVAudioPCMBuffer) -> [Float]? {
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return nil }
        var err: NSError?
        let feed = FeedState()
        converter.convert(to: out, error: &err) { _, status in
            if feed.didFeed { status.pointee = .noDataNow; return nil }
            feed.didFeed = true; status.pointee = .haveData; return buf
        }
        guard err == nil, let ch = out.floatChannelData else { return nil }
        let n = Int(out.frameLength)
        guard n > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: n))
    }
}
