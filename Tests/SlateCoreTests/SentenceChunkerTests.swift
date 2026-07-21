import Testing
@testable import SlateCore

@Suite struct SentenceChunkerTests {
    private func run(_ pieces: [String]) -> [String] {
        var c = SentenceChunker()
        var out: [String] = []
        for p in pieces { out += c.feed(p) }
        out += c.finish()
        return out
    }

    @Test func emitsOnSentenceBoundary() {
        let out = run(["Hallo, ich bin Slate hier. ", "Wie kann ich dir heute helfen?"])
        #expect(out == ["Hallo, ich bin Slate hier.", "Wie kann ich dir heute helfen?"])
    }

    @Test func buffersShortSentencesTogether() {
        // "Ja." alone is under the 25-char minimum → merged with what follows.
        let out = run(["Ja. Das stimmt genau so, wie du sagst."])
        #expect(out == ["Ja. Das stimmt genau so, wie du sagst."])
    }

    @Test func tokensSplitMidWordDontBreakChunks() {
        let out = run(["Die Antw", "ort ist einfach und k", "urz gehalten."])
        #expect(out == ["Die Antwort ist einfach und kurz gehalten."])
    }

    @Test func skipsThinkBlocks() {
        let out = run(["<think>plan the ", "answer</think>Die eigentliche Antwort steht hier."])
        #expect(out == ["Die eigentliche Antwort steht hier."])
    }

    @Test func skipsFencedCode() {
        let out = run(["Hier ist der Code dazu erklärt:\n```swift\nlet x = 1\n```\nMehr braucht es nicht, versprochen."])
        #expect(out == ["Hier ist der Code dazu erklärt:", "Mehr braucht es nicht, versprochen."])
    }

    @Test func stripsInlineMarkdown() {
        let out = run(["Das ist **wirklich** ganz `einfach` gedacht."])
        #expect(out == ["Das ist wirklich ganz einfach gedacht."])
    }

    @Test func doubleNewlineFlushes() {
        let out = run(["Erster Absatz ohne Satzzeichen\n\nZweiter Absatz kommt jetzt dran."])
        #expect(out.first == "Erster Absatz ohne Satzzeichen")
    }

    @Test func finishFlushesRemainder() {
        var c = SentenceChunker()
        #expect(c.feed("Kein Satzende hier").isEmpty)
        #expect(c.finish() == ["Kein Satzende hier"])
    }

    @Test func emptyAndWhitespaceProduceNothing() {
        #expect(run(["   \n  "]).isEmpty)
        #expect(run(["<think>only thoughts</think>"]).isEmpty)
    }
}
