import Foundation
import NaturalLanguage

/// Resolves the language of a spoken turn without sending transcript text off
/// the Mac. Some offline STT engines return only text for auto-detect, so the
/// app needs a local fallback before it tells a small model which language to
/// answer in or hands text to neural TTS.
public enum VoiceLanguage {
    /// Prefer an explicit STT/user choice. Otherwise classify the finished
    /// transcript locally with Apple's on-device language recognizer.
    public static func resolve(reported: String?, transcript: String) -> String? {
        if let reported = normalized(reported) { return reported }

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return normalized(recognizer.dominantLanguage?.rawValue)
    }

    /// A safe local fallback for TTS when an utterance is too short to classify.
    /// It intentionally mirrors the user's macOS language instead of assuming
    /// German, which was the source of English voice turns being forced German.
    public static var systemFallback: String {
        normalized(Locale.preferredLanguages.first) ?? "en"
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let code = raw.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? ""
        guard code != "und", code.count == 2,
              code.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else {
            return nil
        }
        return code
    }
}
