import Testing
@testable import SlateFlowCore

@Test func replacesWrongWithRight() {
    let d = FlowDictionary(entries: [.init(wrong: "lange und co", right: "Lange & Co.")])
    #expect(d.apply(to: "die lange und co beratung") == "die Lange & Co. beratung")
}

@Test func caseInsensitiveMatchKeepsRightCasing() {
    let d = FlowDictionary(entries: [.init(wrong: "slate", right: "Slate")])
    #expect(d.apply(to: "SLATE ist fertig") == "Slate ist fertig")
}

@Test func wordBoundariesOnly() {
    let d = FlowDictionary(entries: [.init(wrong: "co", right: "Co.")])
    #expect(d.apply(to: "das combo läuft") == "das combo läuft")   // no mid-word hits
}

@Test func plainTermsFeedThePromptOnly() {
    // A term without a "wrong" side isn't a replacement — it's prompt vocabulary.
    let d = FlowDictionary(entries: [.init(wrong: "", right: "EUIPO")])
    #expect(d.apply(to: "euipo sagt nein") == "euipo sagt nein")
    #expect(d.promptTerms == ["EUIPO"])
}

@Test func longestWrongWinsFirst() {
    let d = FlowDictionary(entries: [
        .init(wrong: "trade mark", right: "Trademark"),
        .init(wrong: "trade mark radar", right: "Trademark Radar"),
    ])
    #expect(d.apply(to: "das trade mark radar projekt") == "das Trademark Radar projekt")
}
