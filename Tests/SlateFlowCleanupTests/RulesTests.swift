import Testing
@testable import SlateFlowCleanup

// MARK: Spoken punctuation (spec item 5)

@Test func germanSpokenPunctuation() {
    #expect(SpokenPunctuation.apply("hallo neuer absatz wie geht es", language: "de")
            == "hallo\n\nwie geht es")
    #expect(SpokenPunctuation.apply("ja punkt nein komma vielleicht", language: "de")
            == "ja. nein, vielleicht")
    #expect(SpokenPunctuation.apply("wirklich fragezeichen", language: "de") == "wirklich?")
}

@Test func englishSpokenPunctuation() {
    #expect(SpokenPunctuation.apply("yes period no comma maybe new paragraph done", language: "en")
            == "yes. no, maybe\n\ndone")
    #expect(SpokenPunctuation.apply("stop exclamation mark", language: "en") == "stop!")
}

@Test func wordsInsideOtherWordsUntouched() {
    // "kommandant" must not become ",ndant"; "periodic" keeps its "period".
    #expect(SpokenPunctuation.apply("der kommandant kommt", language: "de") == "der kommandant kommt")
    #expect(SpokenPunctuation.apply("periodic checks", language: "en") == "periodic checks")
}

@Test func autoDetectAppliesBothLanguageTables() {
    // language nil → both De and En cues work (auto-detect sessions).
    #expect(SpokenPunctuation.apply("ja punkt", language: nil) == "ja.")
    #expect(SpokenPunctuation.apply("yes period", language: nil) == "yes.")
}

// MARK: Trailing-period policy (spec item 7)

@Test func trailingPeriodPolicy() {
    #expect(TrailingPeriodPolicy.strip("Bis gleich.", appCategory: .messaging, sentences: 1)
            == "Bis gleich")
    #expect(TrailingPeriodPolicy.strip("Satz eins. Satz zwei. Satz drei.", appCategory: .messaging, sentences: 3)
            == "Satz eins. Satz zwei. Satz drei.")
    #expect(TrailingPeriodPolicy.strip("Sehr geehrte Damen.", appCategory: .email, sentences: 1)
            == "Sehr geehrte Damen.")
    #expect(TrailingPeriodPolicy.strip("ok.", appCategory: .other, sentences: 1) == "ok.")
}

@Test func trailingPolicyLeavesOtherEndingsAlone() {
    #expect(TrailingPeriodPolicy.strip("Wirklich?", appCategory: .messaging, sentences: 1) == "Wirklich?")
    #expect(TrailingPeriodPolicy.strip("Los!", appCategory: .messaging, sentences: 1) == "Los!")
}
