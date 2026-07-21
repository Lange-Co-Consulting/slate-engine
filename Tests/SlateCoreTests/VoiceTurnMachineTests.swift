import Testing
@testable import SlateCore

@Suite struct VoiceTurnMachineTests {
    @Test func happyPathTurn() {
        var m = VoiceTurnMachine()
        #expect(m.state == .listening)
        #expect(m.handle(.speechEnd) == [.transcribeUtterance])
        #expect(m.state == .transcribing)
        #expect(m.handle(.transcript("Wie spät ist es?")) == [.appendUser("Wie spät ist es?"), .startLLM("Wie spät ist es?")])
        #expect(m.state == .thinking)
        #expect(m.handle(.llmChunk("Es ist drei Uhr.")) == [.speak("Es ist drei Uhr.")])
        #expect(m.state == .speaking)
        #expect(m.handle(.llmFinished("Es ist drei Uhr.")) == [.appendAssistant("Es ist drei Uhr.")])
        #expect(m.handle(.playbackDrained) == [])
        #expect(m.state == .listening)
    }

    @Test func emptyTranscriptDiscards() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        #expect(m.handle(.transcript("   ")) == [.discardUtterance])
        #expect(m.state == .listening)
    }

    @Test func bargeInWhileThinkingCancels() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Erzähl mir was Langes bitte."))
        #expect(m.state == .thinking)
        #expect(m.handle(.bargeIn) == [.cancelLLM])
        #expect(m.state == .listening)
    }

    @Test func bargeInWhileSpeakingStopsAndCancels() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Frage."))
        _ = m.handle(.llmChunk("Lange Antwort Teil eins."))
        #expect(m.state == .speaking)
        #expect(m.handle(.bargeIn) == [.stopSpeaking, .cancelLLM])
        #expect(m.state == .listening)
    }

    @Test func llmFinishedWithoutChunksStillAppendsAndSpeaksFinalText() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Hm?"))
        // Model produced no speakable chunk (e.g. only a think block) but a final text.
        #expect(m.handle(.llmFinished("Ok.")) == [.appendAssistant("Ok."), .speak("Ok.")])
        #expect(m.state == .speaking)
    }

    @Test func llmFailedRecoversToListening() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Frage."))
        #expect(m.handle(.llmFailed) == [.stopSpeaking])
        #expect(m.state == .listening)
    }

    @Test func drainBeforeLLMFinishedKeepsSpeaking() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Frage."))
        _ = m.handle(.llmChunk("Teil eins."))
        // Player drained but tokens still coming → stay in speaking, wait.
        #expect(m.handle(.playbackDrained) == [])
        #expect(m.state == .speaking)
        _ = m.handle(.llmFinished("Teil eins. Teil zwei."))
        #expect(m.handle(.playbackDrained) == [])
        #expect(m.state == .listening)
    }

    @Test func transcriptPartialReturnsToListeningWithoutCommitting() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        #expect(m.state == .transcribing)
        #expect(m.handle(.transcriptPartial) == [])
        #expect(m.state == .listening)
    }

    @Test func endFromAnyStateStopsEverything() {
        var m = VoiceTurnMachine()
        _ = m.handle(.speechEnd)
        _ = m.handle(.transcript("Frage."))
        _ = m.handle(.llmChunk("Antwort."))
        #expect(m.handle(.end) == [.stopSpeaking, .cancelLLM])
        #expect(m.state == .idle)
    }
}
