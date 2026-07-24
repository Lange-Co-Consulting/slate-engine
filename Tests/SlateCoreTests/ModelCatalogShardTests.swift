import Foundation
import Testing
@testable import SlateCore

@Suite("Split-GGUF shards collapse into one model")
struct ModelCatalogShardTests {
    private func e(_ path: String, _ bytes: Int64) -> ModelEntry {
        ModelEntry(url: URL(fileURLWithPath: path), bytes: bytes)
    }

    @Test("A multi-part model lists once, with the summed size")
    func collapsesShards() {
        let out = ModelCatalog.collapseShards([
            e("/m/Big-Model-Q8-00001-of-00003.gguf", 40),
            e("/m/Big-Model-Q8-00002-of-00003.gguf", 40),
            e("/m/Big-Model-Q8-00003-of-00003.gguf", 20),
        ])
        #expect(out.count == 1)
        #expect(out.first?.url.lastPathComponent == "Big-Model-Q8-00001-of-00003.gguf")
        #expect(out.first?.bytes == 100)   // the whole set, not just part 1
    }

    @Test("Single-file models are untouched")
    func keepsSingles() {
        let out = ModelCatalog.collapseShards([e("/m/Qwen3-8B-Q4.gguf", 5)])
        #expect(out.count == 1 && out.first?.bytes == 5)
    }

    @Test("Two different split sets stay separate")
    func separatesSets() {
        let out = ModelCatalog.collapseShards([
            e("/m/A-00001-of-00002.gguf", 1), e("/m/A-00002-of-00002.gguf", 1),
            e("/m/B-00001-of-00002.gguf", 2), e("/m/B-00002-of-00002.gguf", 2),
        ])
        #expect(out.count == 2)
        #expect(Set(out.map(\.bytes)) == Set([2, 4]))
    }

    @Test("An incomplete set without part 1 is not listed")
    func dropsIncomplete() {
        let out = ModelCatalog.collapseShards([e("/m/C-00002-of-00002.gguf", 3)])
        #expect(out.isEmpty)
    }

    @Test("Ordinary names with digits are not mistaken for shards")
    func ignoresNonShards() {
        #expect(ModelCatalog.shardInfo(URL(fileURLWithPath: "/m/Llama-3-8B.gguf")) == nil)
        #expect(ModelCatalog.shardInfo(URL(fileURLWithPath: "/m/Qwen2-5-7B-Q4-K-M.gguf")) == nil)
    }
}

@Suite("Split models are sized by the whole set")
struct ShardSizingTests {
    @Test("totalBytes sums every shard, not just the first")
    func sumsShards() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shard-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["Big-00001-of-00003.gguf", "Big-00002-of-00003.gguf", "Big-00003-of-00003.gguf"]
        for (i, n) in names.enumerated() {
            try Data(repeating: 0, count: 1000 * (i + 1)).write(to: dir.appendingPathComponent(n))
        }
        let first = dir.appendingPathComponent(names[0])
        #expect(ModelCatalog.totalBytes(of: first) == 6000)   // 1000+2000+3000, not 1000
    }

    @Test("A single-file model reports its own size")
    func singleFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("single-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("Solo-Q4.gguf")
        try Data(repeating: 0, count: 4321).write(to: f)
        #expect(ModelCatalog.totalBytes(of: f) == 4321)
    }
}
