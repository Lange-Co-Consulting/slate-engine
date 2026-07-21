import Foundation
import FluidAudio

/// Streaming Silero VAD (FluidAudio) behind a Slate-shaped API: feed 16 kHz
/// mono samples in any batch size, get speech start/end events out. The
/// Silero model downloads once on prepare() (a few MB), offline afterwards.
public actor StreamingVad {
    public enum Event: Sendable, Equatable { case speechStart, speechEnd }

    private var vad: VadManager?
    private var state: VadStreamState?
    private var pending: [Float] = []
    private let segmentation: VadSegmentationConfig
    private var importedModelDirectory: URL?

    /// `minSilence`: how long a pause ends the utterance (0.6 s - snappier than
    /// Silero's 0.75 default but still tolerant of mid-sentence thinking pauses).
    public init(minSilence: TimeInterval = 0.6) {
        var cfg = VadSegmentationConfig.default
        cfg.minSilenceDuration = minSilence
        segmentation = cfg
        ModelHub.offlineMode = true
        if let path = UserDefaults.standard.string(forKey: "slate.vadModelDirectory") {
            importedModelDirectory = URL(fileURLWithPath: path)
        }
    }

    public func prepare() async throws {
        guard vad == nil else { return }
        ModelHub.offlineMode = true
        let v = if let importedModelDirectory {
            try await VadManager(config: VadConfig(), modelDirectory: importedModelDirectory)
        } else {
            try await VadManager(config: VadConfig())
        }
        state = await v.makeStreamState()
        vad = v
    }

    public func downloadAndPrepare() async throws {
        vad = nil; state = nil
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        let v = try await VadManager(config: VadConfig())
        state = await v.makeStreamState(); vad = v
    }

    public func useImportedModels(at directory: URL) async throws {
        vad = nil; state = nil
        importedModelDirectory = directory
        UserDefaults.standard.set(directory.path, forKey: "slate.vadModelDirectory")
        try await prepare()
    }

    /// Feed captured samples; returns events crossed inside this batch.
    public func feed(_ samples: [Float]) async throws -> [Event] {
        guard let vad, var s = state else { return [] }
        pending.append(contentsOf: samples)
        var events: [Event] = []
        while pending.count >= VadManager.chunkSize {
            let chunk = Array(pending.prefix(VadManager.chunkSize))
            pending.removeFirst(VadManager.chunkSize)
            let r = try await vad.processStreamingChunk(chunk, state: s,
                                                        config: segmentation,
                                                        returnSeconds: false)
            s = r.state
            if let e = r.event { events.append(e.isStart ? .speechStart : .speechEnd) }
        }
        state = s
        return events
    }

    /// Fresh stream (session start / mute toggled).
    public func reset() async {
        if let vad { state = await vad.makeStreamState() }
        pending = []
    }
}
