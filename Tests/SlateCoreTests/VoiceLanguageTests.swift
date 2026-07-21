import Testing
@testable import SlateCore

@Suite struct VoiceLanguageTests {
    @Test func explicitLanguageWinsOverRecognition() {
        #expect(VoiceLanguage.resolve(reported: "en-US", transcript: "Wie spät ist es?") == "en")
    }

    @Test func recognizesEnglishTranscriptLocally() {
        #expect(VoiceLanguage.resolve(reported: nil,
                                      transcript: "What color is the sky on a clear day?") == "en")
    }

    @Test func recognizesGermanTranscriptLocally() {
        #expect(VoiceLanguage.resolve(reported: nil,
                                      transcript: "Wie ist das Wetter heute in Berlin?") == "de")
    }

    @Test func unknownOrShortTranscriptDoesNotForceGerman() {
        #expect(VoiceLanguage.resolve(reported: nil, transcript: "…") == nil)
    }
}
