import Foundation
import FluidAudio

// FluidAudio's offline manager is internally immutable after model preparation.
// Slate owns it inside one actor, so no concurrent caller can reach it.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

/// Parakeet-tdt-0.6b-v3 on CoreML (encoder on the Neural Engine) via FluidAudio.
/// v3 = 25 languages incl. German. Models (~600 MB int8) download once from HF
/// into Application Support and run fully offline afterwards - same lifecycle
/// as Slate's GGUFs. The GPU stays free for llama.cpp cleanup by design.
public actor ParakeetEngine: STTEngine {
    private var manager: AsrManager?
    private var diarizer: OfflineDiarizerManager?
    private var preparing: Task<Void, Error>?
    private var importedModelDirectory: URL?

    public init() {
        // Runtime is offline by default. Downloads are enabled only inside the
        // explicit user-triggered `downloadAndPrepare` method below.
        ModelHub.offlineMode = true
        if let path = UserDefaults.standard.string(forKey: "slate.parakeetModelDirectory") {
            importedModelDirectory = URL(fileURLWithPath: path)
        }
    }

    public var isReady: Bool { manager != nil }

    /// Idempotent + coalescing local load. This path is network-disabled and
    /// succeeds from FluidAudio's cache or a user-imported model directory.
    public func prepare() async throws {
        if manager != nil { return }
        if let preparing { return try await preparing.value }
        let task = Task<Void, Error> {
            ModelHub.offlineMode = true
            let models: AsrModels
            if let importedModelDirectory {
                models = try await AsrModels.load(from: importedModelDirectory, version: .v3)
            } else {
                models = try await AsrModels.loadFromCache(version: .v3)
            }
            let m = AsrManager(config: .default)
            try await m.loadModels(models)
            manager = m
        }
        preparing = task
        defer { preparing = nil }
        try await task.value
    }

    /// Explicit network provisioning. The user must press a Download button;
    /// ordinary transcription and app launch never enter this path.
    public func downloadAndPrepare() async throws {
        manager = nil
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
    }

    /// Use a complete Parakeet folder copied onto an air-gapped Mac.
    public func useImportedModels(at directory: URL) async throws {
        manager = nil
        ModelHub.offlineMode = true
        let models = try await AsrModels.load(from: directory, version: .v3)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        importedModelDirectory = directory
        UserDefaults.standard.set(directory.path, forKey: "slate.parakeetModelDirectory")
        manager = m
    }

    public func transcribe(_ samples: [Float], language: String?) async throws -> FlowTranscript {
        try await prepare()
        guard let manager else { throw STTError.notReady }
        guard !samples.isEmpty else { throw STTError.empty }
        var state = try TdtDecoderState()
        let lang = language.flatMap { Language(rawValue: $0) }
        let result = try await manager.transcribe(samples, decoderState: &state, language: lang)
        return FlowTranscript(text: result.text)
    }

    public func transcribeWithSpeakers(_ samples: [Float], language: String?,
                                       diarizerModelDirectory: URL? = nil) async throws -> [SpeakerTranscriptSegment] {
        try await prepare()
        guard !samples.isEmpty else { throw STTError.empty }
        ModelHub.offlineMode = true
        let d: OfflineDiarizerManager
        if let diarizer { d = diarizer }
        else {
            let created = OfflineDiarizerManager()
            try await created.prepareModels(directory: diarizerModelDirectory)
            diarizer = created
            d = created
        }
        let result = try await d.process(audio: samples)
        let merged = Self.merge(result.segments)
        var output: [SpeakerTranscriptSegment] = []
        for segment in merged {
            let start = max(0, Int(Double(segment.start) * 16_000))
            let end = min(samples.count, Int(Double(segment.end) * 16_000))
            guard end - start >= 1_600 else { continue }
            let transcript = try await transcribe(Array(samples[start..<end]), language: language)
            let clean = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                output.append(.init(speaker: segment.speaker, startSeconds: Double(segment.start),
                                    endSeconds: Double(segment.end), text: clean))
            }
        }
        return output
    }

    /// Explicit user-triggered provisioning for the speaker model bundle.
    public func downloadAndPrepareDiarizer() async throws {
        diarizer = nil
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        let created = OfflineDiarizerManager()
        try await created.prepareModels()
        diarizer = created
    }

    private static func merge(_ segments: [TimedSpeakerSegment]) -> [(speaker: String, start: Float, end: Float)] {
        var merged: [(speaker: String, start: Float, end: Float)] = []
        for segment in segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
            guard segment.endTimeSeconds > segment.startTimeSeconds else { continue }
            if let last = merged.last,
               last.speaker == segment.speakerId,
               segment.startTimeSeconds - last.end < 0.8 {
                merged[merged.count - 1].end = max(last.end, segment.endTimeSeconds)
            } else {
                merged.append((segment.speakerId, segment.startTimeSeconds, segment.endTimeSeconds))
            }
        }
        return merged
    }
}

public struct SpeakerTranscriptSegment: Sendable, Equatable {
    public let speaker: String
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String

    public init(speaker: String, startSeconds: Double, endSeconds: Double, text: String) {
        self.speaker = speaker; self.startSeconds = startSeconds
        self.endSeconds = endSeconds; self.text = text
    }

    public var formatted: String {
        let total = max(0, Int(startSeconds.rounded()))
        return String(format: "[%02d:%02d] %@: %@", total / 60, total % 60,
                      speaker.replacingOccurrences(of: "S", with: "Speaker "), text)
    }
}
