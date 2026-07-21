import Foundation

/// Pure turn-taking brain of a voice session: events in, commands out.
/// No audio, no LLM, no timers - the IO shell (VoiceSession) executes commands.
public struct VoiceTurnMachine: Sendable {
    public enum State: Equatable, Sendable { case idle, listening, transcribing, thinking, speaking }
    public enum Event: Equatable, Sendable {
        case speechEnd              // VAD closed an utterance while listening
        case transcript(String)     // ASR result (may be blank noise)
        /// The user kept talking while we transcribed - the shell stashes the
        /// partial text and stitches it to the continuation; just resume listening.
        case transcriptPartial
        case llmChunk(String)       // speakable chunk from SentenceChunker
        case llmFinished(String)    // full cleaned answer text
        case llmFailed
        case playbackDrained        // player queue ran dry
        case bargeIn                // user spoke while Slate was thinking/speaking
        case end                    // user closed the session
    }
    public enum Command: Equatable, Sendable {
        case transcribeUtterance
        case discardUtterance
        case appendUser(String)
        case startLLM(String)
        case speak(String)
        case stopSpeaking
        case cancelLLM
        case appendAssistant(String)
    }

    public private(set) var state: State = .listening
    /// Tokens still streaming? Drain only ends the turn once the LLM finished.
    private var llmDone = false
    /// Whether any chunk was handed to the player this turn.
    private var spokeAnything = false

    public init() {}

    public mutating func handle(_ event: Event) -> [Command] {
        switch (state, event) {
        case (_, .end):
            state = .idle
            return [.stopSpeaking, .cancelLLM]

        case (.listening, .speechEnd):
            state = .transcribing
            return [.transcribeUtterance]

        case (.transcribing, .transcriptPartial):
            state = .listening
            return []

        case (.transcribing, .transcript(let raw)):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                state = .listening
                return [.discardUtterance]
            }
            state = .thinking
            llmDone = false
            spokeAnything = false
            return [.appendUser(text), .startLLM(text)]

        case (.thinking, .llmChunk(let c)), (.speaking, .llmChunk(let c)):
            state = .speaking
            spokeAnything = true
            return [.speak(c)]

        case (.thinking, .llmFinished(let full)), (.speaking, .llmFinished(let full)):
            llmDone = true
            var cmds: [Command] = [.appendAssistant(full)]
            if !spokeAnything {
                // Nothing reached the player (e.g. all-think stream) - speak the
                // final text so the turn is never silently swallowed.
                let t = full.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty {
                    state = .listening
                } else {
                    state = .speaking
                    spokeAnything = true
                    cmds.append(.speak(t))
                }
            }
            return cmds

        case (.speaking, .playbackDrained):
            if llmDone { state = .listening }
            return []

        case (.thinking, .bargeIn):
            state = .listening
            return [.cancelLLM]

        case (.speaking, .bargeIn):
            state = .listening
            return [.stopSpeaking, .cancelLLM]

        case (.thinking, .llmFailed), (.speaking, .llmFailed):
            state = .listening
            return [.stopSpeaking]

        default:
            return []
        }
    }
}

/// Prompt + generation defaults for spoken turns.
public enum VoicePrompt {
    /// System prompt for a spoken turn. When the detected `language` is known it is
    /// stated EXPLICITLY (by name) with a hard instruction - small local models
    /// otherwise drift to English even when the user spoke German, which then also
    /// makes the TTS mispronounce (English words through the German voice).
    public static func system(language: String? = nil) -> String {
        let langLine: String
        if let language, let name = languageName(language) {
            langLine = "The user is speaking \(name). You MUST reply ONLY in \(name) - "
                     + "never switch to English or any other language. "
        } else {
            langLine = "Reply in the same language the user spoke. "
        }
        return """
        You are Slate, speaking OUT LOUD in a live voice conversation. \(langLine)Keep it \
        short and conversational - a few natural spoken sentences. Never use lists, \
        markdown, or code blocks; if the answer would need code or long detail, give a \
        one-sentence summary and suggest continuing in the typed chat.
        """
    }

    /// BCP-47 code → English language name for the prompt. nil = leave it to the model.
    static func languageName(_ code: String) -> String? {
        let map: [String: String] = [
            "de": "German", "en": "English", "fr": "French", "es": "Spanish",
            "it": "Italian", "pt": "Portuguese", "nl": "Dutch", "pl": "Polish",
            "ru": "Russian", "tr": "Turkish", "ja": "Japanese", "ko": "Korean",
            "zh": "Chinese", "ar": "Arabic", "hi": "Hindi", "sv": "Swedish",
            "da": "Danish", "nb": "Norwegian", "no": "Norwegian", "fi": "Finnish",
            "cs": "Czech", "uk": "Ukrainian", "ro": "Romanian", "hu": "Hungarian",
            "el": "Greek", "bg": "Bulgarian", "hr": "Croatian", "sk": "Slovak",
        ]
        return map[String(code.prefix(2)).lowercased()]
    }

    public static let maxTokens = 300
    public static let temperature = 0.4
}
