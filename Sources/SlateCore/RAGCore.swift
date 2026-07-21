import Foundation

/// Splits documents into overlapping word-windows for embedding + retrieval.
public enum TextChunker {
    /// `maxWords` per chunk, sliding by `maxWords - overlap` so adjacent chunks
    /// share context (retrieval doesn't lose a sentence split across a boundary).
    public static func chunk(_ text: String, maxWords: Int = 300, overlap: Int = 50) -> [String] {
        let words = text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
        guard !words.isEmpty else { return [] }
        guard words.count > maxWords else { return [words.joined(separator: " ")] }
        let step = max(1, maxWords - overlap)
        var chunks: [String] = []
        var i = 0
        while i < words.count {
            let slice = words[i..<min(i + maxWords, words.count)]
            chunks.append(slice.joined(separator: " "))
            if i + maxWords >= words.count { break }
            i += step
        }
        return chunks
    }
}

/// In-memory vector store with cosine top-k. Small local knowledge bases only  - 
/// linear scan is plenty for a few thousand chunks.
public struct VectorIndex: Sendable, Codable {
    public struct Entry: Sendable, Codable { public let id: String; public let vector: [Float] }
    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func add(id: String, vector: [Float]) {
        entries.append(Entry(id: id, vector: vector))
    }

    public func topK(_ query: [Float], k: Int) -> [(id: String, score: Float)] {
        guard !entries.isEmpty, k > 0 else { return [] }
        return entries
            .map { (id: $0.id, score: Self.cosine(query, $0.vector)) }
            .sorted { $0.score > $1.score }
            .prefix(k)
            .map { $0 }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}

/// Builds the retrieved-context block prepended to a grounded (RAG) turn.
public enum RAGPrompt {
    public struct Source: Sendable, Equatable { public let ref: Int; public let file: String; public let text: String
        public init(ref: Int, file: String, text: String) { self.ref = ref; self.file = file; self.text = text } }

    public static func systemAddendum(_ sources: [Source]) -> String {
        guard !sources.isEmpty else { return "" }
        var out = """
        Use the following retrieved excerpts from the user's own files to answer. \
        Ground your answer in them and cite the relevant excerpt inline as [n]. \
        If the excerpts don't contain the answer, say so plainly.

        """
        for s in sources {
            out += "\n[\(s.ref)] \(s.file):\n\(s.text)\n"
        }
        return out
    }
}
