import Foundation
import Testing
@testable import SlateCore

@Suite struct RAGCoreTests {
    // MARK: TextChunker
    @Test func shortTextIsOneChunk() {
        let c = TextChunker.chunk("hello world here", maxWords: 300, overlap: 50)
        #expect(c == ["hello world here"])
    }
    @Test func emptyTextChunksToNothing() {
        #expect(TextChunker.chunk("   \n ", maxWords: 10, overlap: 2).isEmpty)
    }
    @Test func longTextSplitsWithOverlap() {
        let words = (1...25).map { "w\($0)" }.joined(separator: " ")
        let c = TextChunker.chunk(words, maxWords: 10, overlap: 3)
        #expect(c.count >= 3)                 // 25 words / (10-3 step) ≈ 4 chunks
        #expect(c[0].split(separator: " ").count == 10)
        // Overlap: the last 3 words of chunk 0 begin chunk 1.
        let tail0 = c[0].split(separator: " ").suffix(3).joined(separator: " ")
        #expect(c[1].hasPrefix(tail0))
    }

    // MARK: VectorIndex
    @Test func cosineIdentityAndOrthogonal() {
        #expect(abs(VectorIndex.cosine([1, 0], [1, 0]) - 1) < 1e-6)
        #expect(abs(VectorIndex.cosine([1, 0], [0, 1])) < 1e-6)
    }
    @Test func topKReturnsNearest() {
        var idx = VectorIndex()
        idx.add(id: "a", vector: [1, 0, 0])
        idx.add(id: "b", vector: [0, 1, 0])
        idx.add(id: "c", vector: [0.9, 0.1, 0])
        let hits = idx.topK([1, 0, 0], k: 2)
        #expect(hits.map(\.id) == ["a", "c"])   // a exact, c close
    }
    @Test func topKEmptyIndex() {
        #expect(VectorIndex().topK([1, 0], k: 3).isEmpty)
    }

    // MARK: RAGPrompt
    @Test func systemAddendumListsNumberedSources() {
        let add = RAGPrompt.systemAddendum([
            .init(ref: 1, file: "notes.md", text: "The sky is blue."),
            .init(ref: 2, file: "facts.txt", text: "Water is wet."),
        ])
        #expect(add.contains("[1]"))
        #expect(add.contains("notes.md"))
        #expect(add.contains("The sky is blue."))
        #expect(add.contains("[2]"))
        #expect(add.localizedCaseInsensitiveContains("cite"))
    }
    @Test func systemAddendumEmptyWhenNoSources() {
        #expect(RAGPrompt.systemAddendum([]).isEmpty)
    }
}
