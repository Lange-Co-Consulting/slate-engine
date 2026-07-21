import Testing
@testable import SlateCore

private let roster = [
    RoundtableParticipant(id: "a", name: "Alice", persona: "the optimist", index: 0),
    RoundtableParticipant(id: "b", name: "Bob", persona: "", index: 1),
    RoundtableParticipant(id: "c", name: "Cara", persona: "the skeptic", index: 2),
]

@Test func localMemoryEstimateUsesBoundedRoundtableContext() {
    let estimate = Roundtable.estimatedLocalMemoryGB(fileSizesGB: [1.9, 1.1])
    #expect(Roundtable.localContextWindow == 8_192)
    #expect(estimate > 5.3 && estimate < 5.5)
}

@Test func localMemoryEstimateIgnoresInvalidSizesAndMatchesCustomContext() {
    let estimate = Roundtable.estimatedLocalMemoryGB(
        fileSizesGB: [2.0, -.infinity, .nan], contextTokens: 0)
    #expect(estimate == 2.0)
}

@Test func stripNameEchoRemovesSelfLabels() {
    // The echoes seen in real transcripts: bracketed, plain, and bold name prefixes.
    #expect(Roundtable.stripNameEcho("[Mistral 7B]: Absolutely, the S63…", speaker: "Mistral 7B") == "Absolutely, the S63…")
    #expect(Roundtable.stripNameEcho("Mistral 7B: I agree.", speaker: "Mistral 7B") == "I agree.")
    #expect(Roundtable.stripNameEcho("**Mistral 7B**: I agree.", speaker: "Mistral 7B") == "I agree.")
    #expect(Roundtable.stripNameEcho("[Qwen2.5 3B]: Point taken.", speaker: "Mistral 7B") == "Point taken.")  // any bracket label is an echo
    // Addressing ANOTHER participant mid-sentence is content - untouched.
    #expect(Roundtable.stripNameEcho("A compelling perspective, Llama 3.2 3B. Yet…", speaker: "Qwen2.5 3B")
            == "A compelling perspective, Llama 3.2 3B. Yet…")
    #expect(Roundtable.stripNameEcho("Plain answer with no prefix.", speaker: "Mistral 7B") == "Plain answer with no prefix.")
}

@Test func clampAnswerBoundsVerboseTurns() {
    // Keeps whole sentences up to the limit (default 4) - guarantees brevity even
    // when a reasoning model ignores the "2-3 sentences" instruction.
    let long = "One. Two. Three. Four. Five. Six."
    #expect(Roundtable.clampAnswer(long, maxSentences: 4) == "One. Two. Three. Four.")
    // Short answers pass through untouched.
    #expect(Roundtable.clampAnswer("Just one thought here.") == "Just one thought here.")
    // A run-on with no sentence punctuation is hard-capped by characters.
    let runOn = String(repeating: "word ", count: 400)   // ~2000 chars, no punctuation
    #expect(Roundtable.clampAnswer(runOn).count <= 701)
    #expect(Roundtable.clampAnswer("").isEmpty)
}

@Test func systemPromptForbidsThinkingAndIsConcise() {
    // The no-reasoning directive is what stops a reasoning seat from spending its
    // whole turn thinking and emitting no visible answer (which made the other
    // model look like it answered several times in a row).
    let sp = Roundtable.systemPrompt(for: roster[1], roster: roster, topic: "x",
                                     round: 0, totalRounds: 3, isSynthesis: false).lowercased()
    #expect(sp.contains("<think>"))
    #expect(sp.contains("do not think out loud") || sp.contains("do not think"))
    #expect(sp.contains("2-3 sentences"))
    // Generation ceiling must exceed the short-answer target so reasoning seats can
    // think AND still reach their answer.
    #expect(Roundtable.maxTurnTokens > Roundtable.maxResponseTokens)
}

@Test func systemPromptNamesSelfOthersAndPersona() {
    let sp = Roundtable.systemPrompt(for: roster[0], roster: roster, topic: "AGI safety",
                                     round: 0, totalRounds: 3, isSynthesis: false)
    #expect(sp.contains("Alice"))
    #expect(sp.contains("Bob") && sp.contains("Cara"))
    #expect(sp.contains("the optimist"))
    #expect(sp.contains("AGI safety"))
    #expect(sp.contains("round 1 of 3"))
    #expect(!sp.lowercased().contains("synthesis"))
}

@Test func systemPromptSynthesisWordingAndNoEmptyPersona() {
    let sp = Roundtable.systemPrompt(for: roster[1], roster: roster, topic: "X",
                                     round: 3, totalRounds: 3, isSynthesis: true)
    #expect(sp.lowercased().contains("synthesis"))
    #expect(!sp.contains("Your role in this discussion"))   // Bob has no persona → no persona line
}

@Test func promptRelabelsPerSpeaker() {
    let discussion = [
        ChatMessage(role: .assistant, content: "Opt take", speaker: "Alice", speakerIndex: 0),
        ChatMessage(role: .assistant, content: "Counter", speaker: "Cara", speakerIndex: 2),
    ]
    let msgs = Roundtable.prompt(for: roster[0], roster: roster, topic: "T",
                                 discussion: discussion, round: 1, totalRounds: 3, isSynthesis: false)
    #expect(msgs.first?.role == .system)
    #expect(msgs[1].role == .user && msgs[1].content.contains("T"))          // topic seed
    #expect(msgs.contains { $0.role == .assistant && $0.content == "Opt take" })  // own turn kept as assistant
    #expect(msgs.contains { $0.role == .user && $0.content == "[Cara]: Counter" }) // other → user w/ name
    #expect(msgs.last?.role == .user)                                        // ends on a user turn
}

@Test func promptAppendsUserNudgeWhenLastTurnIsSelf() {
    let discussion = [ChatMessage(role: .assistant, content: "mine", speaker: "Alice", speakerIndex: 0)]
    let msgs = Roundtable.prompt(for: roster[0], roster: roster, topic: "T",
                                 discussion: discussion, round: 1, totalRounds: 3, isSynthesis: false)
    #expect(msgs.last?.role == .user)
}

@Test func speakerOrderNormalVsSynthesis() {
    #expect(Roundtable.speakerOrder(roster: roster, synthesis: false).count == 3)
    #expect(Roundtable.speakerOrder(roster: roster, synthesis: true).map(\.name) == ["Alice"])
    #expect(Roundtable.speakerOrder(roster: [], synthesis: true).isEmpty)
}

@Test func currentDiscussionScopesToLastTopic() {
    // A second topic in the same conversation must NOT replay topic A's turns.
    let msgs: [ChatMessage] = [
        ChatMessage(role: .user, content: "topic A"),
        ChatMessage(role: .assistant, content: "A1", speaker: "Alice", speakerIndex: 0),
        ChatMessage(role: .assistant, content: "A2", speaker: "Bob", speakerIndex: 1),
        ChatMessage(role: .user, content: "topic B"),
        ChatMessage(role: .assistant, content: "B1", speaker: "Alice", speakerIndex: 0),
    ]
    #expect(Roundtable.currentDiscussion(in: msgs).map(\.content) == ["B1"])
}

@Test func currentDiscussionEmptyForFreshTopic() {
    // First speaker of a topic sees no prior discussion (topic is the last message).
    #expect(Roundtable.currentDiscussion(in: [ChatMessage(role: .user, content: "t")]).isEmpty)
}

@Test func currentDiscussionExcludesUnattributed() {
    // A failed seat's error notice (no speaker) is not replayed as a turn.
    let msgs: [ChatMessage] = [
        ChatMessage(role: .user, content: "t"),
        ChatMessage(role: .assistant, content: "⚠️ rate limited"),
        ChatMessage(role: .assistant, content: "real", speaker: "Alice", speakerIndex: 0),
    ]
    #expect(Roundtable.currentDiscussion(in: msgs).map(\.content) == ["real"])
}
