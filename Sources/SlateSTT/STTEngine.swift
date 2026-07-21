import Foundation

/// A finished transcription. `detectedLanguage` is BCP-47 ("de", "en") when the
/// engine reports it; nil otherwise.
public struct FlowTranscript: Sendable, Equatable {
    public var text: String
    public var detectedLanguage: String?
    public init(text: String, detectedLanguage: String? = nil) {
        self.text = text; self.detectedLanguage = detectedLanguage
    }
}

/// Speech-to-text engine boundary for Slate Flow. Implementations: Parakeet
/// (FluidAudio/ANE), later Apple SpeechTranscriber / whisper.cpp if needed.
public protocol STTEngine: Sendable {
    /// 16 kHz mono Float32 samples → transcript. `language` nil = auto-detect.
    func transcribe(_ samples: [Float], language: String?) async throws -> FlowTranscript
    var isReady: Bool { get async }
    /// Downloads/loads models as needed. Safe to call repeatedly.
    func prepare() async throws
}

public enum STTError: Error, Sendable { case notReady, empty }
