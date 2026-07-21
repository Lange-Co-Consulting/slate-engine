import Foundation
import FluidAudio

/// Offline neural TTS - Supertonic-3 on CoreML/ANE via FluidAudio (31 languages
/// incl. German, 44.1 kHz mono). Mirrors ParakeetEngine: this file is the ONLY
/// place that touches FluidAudio TTS types. Normal preparation is strictly
/// offline; provisioning is a separate, explicit user action.
public actor SupertonicTTS {
    public static let sampleRate: Double = 44_100

    private var manager: Supertonic3Manager?
    private var styles: [String: Supertonic3VoiceStyle] = [:]
    private var preparing: Task<Void, Error>?
    private var importedModelDirectory: URL?

    public init() {
        ModelHub.offlineMode = true
        if let path = UserDefaults.standard.string(forKey: "slate.supertonicModelDirectory") {
            importedModelDirectory = URL(fileURLWithPath: path)
        }
    }

    public var isReady: Bool { manager != nil && !styles.isEmpty }

    /// Cache/import-only CoreML load (idempotent, coalesces concurrent callers).
    public func prepare(voices: [String] = ["F1"],
                        progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if isReady { return }
        if let running = preparing { return try await running.value }
        let task = Task { [voices] in
            ModelHub.offlineMode = true
            // "ane-int4" = Supertonic3VectorEstimator.aneBucketed(.int4)'s download
            // variant token (the enum property is internal - token hardcoded).
            _ = try await Supertonic3ResourceDownloader.ensureModels(
                directory: importedModelDirectory, veVariant: "ane-int4") { p in
                progress?(p.fractionCompleted)
            }
            let m = try await Supertonic3Manager.downloadAndCreate(
                cacheDirectory: importedModelDirectory,
                computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))
            var loaded: [String: Supertonic3VoiceStyle] = [:]
            for name in voices {
                guard let v = Supertonic3Voice(name: name) else { continue }
                loaded[name] = try await Supertonic3ResourceDownloader.loadVoiceStyle(
                    v, directory: importedModelDirectory)
            }
            self.install(manager: m, styles: loaded)
            // Warm the lazily-compiled ANE bucket so the first real sentence is fast.
            if let style = loaded.values.first {
                _ = try? await m.synthesize(text: "Hallo.", language: "de", style: style)
            }
        }
        preparing = task
        defer { preparing = nil }
        try await task.value
    }

    /// Prepare from cache; when the model is not provisioned yet AND the caller
    /// allows it, download it once (so picking a neural voice actually delivers
    /// that voice instead of silently falling back to a system voice forever).
    public func prepareAllowingDownload(voices: [String],
                                        allowDownload: Bool,
                                        progress: (@Sendable (Double) -> Void)? = nil) async throws {
        do {
            try await prepare(voices: voices, progress: progress)
        } catch {
            guard allowDownload else { throw error }
            try await downloadAndPrepare(voices: voices, progress: progress)
        }
    }

    /// Explicit one-time provisioning. Only this method enables networking.
    public func downloadAndPrepare(voices: [String] = ["M1", "F1"],
                                   progress: (@Sendable (Double) -> Void)? = nil) async throws {
        manager = nil; styles = [:]
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        _ = try await Supertonic3ResourceDownloader.ensureModels(veVariant: "ane-int4") { p in
            progress?(p.fractionCompleted)
        }
        let m = try await Supertonic3Manager.downloadAndCreate(
            computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))
        var loaded: [String: Supertonic3VoiceStyle] = [:]
        for name in voices {
            guard let voice = Supertonic3Voice(name: name) else { continue }
            loaded[name] = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice)
        }
        install(manager: m, styles: loaded)
    }

    /// Use a copied FluidAudio TTS cache root on an air-gapped Mac.
    public func useImportedModels(at directory: URL, voices: [String] = ["M1", "F1"]) async throws {
        manager = nil; styles = [:]
        importedModelDirectory = directory
        UserDefaults.standard.set(directory.path, forKey: "slate.supertonicModelDirectory")
        try await prepare(voices: voices)
    }

    private func install(manager m: Supertonic3Manager, styles s: [String: Supertonic3VoiceStyle]) {
        manager = m
        styles = s
    }

    /// Synthesize one speakable chunk → 44.1 kHz mono Float32 samples.
    /// Unsupported language codes fall back to "en".
    public func synthesize(_ text: String, language: String, voice: String = "F1") async throws -> [Float] {
        guard let manager, let style = styles[voice] ?? styles.values.first else {
            throw STTError.notReady
        }
        let lang = Supertonic3Constants.availableLanguages.contains(language) ? language : "en"
        return try await manager.synthesize(text: text, language: lang, style: style).samples
    }

    /// Frees the CoreML models (voice session ended).
    public func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil
        styles = [:]
    }
}
