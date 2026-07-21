import Testing
import Foundation
@testable import SlateCore

@Test func catalogSkipsMMProjAndPairsItToTheModel() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-catalog-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let model = dir.appendingPathComponent("Gemma-4-it-Q4.gguf")
    let proj  = dir.appendingPathComponent("mmproj-Gemma-4-f16.gguf")
    try Data("x".utf8).write(to: model)
    try Data("x".utf8).write(to: proj)

    // The projector must not show up as a selectable chat model.
    let entries = ModelCatalog.scan(directories: [dir])
    #expect(entries.count == 1)
    #expect(entries.first?.url.lastPathComponent == "Gemma-4-it-Q4.gguf")

    // …but it pairs to its sibling model.
    #expect(ModelCatalog.mmproj(for: model)?.lastPathComponent == "mmproj-Gemma-4-f16.gguf")
}

@Test func mmprojPicksTheMatchingProjectorAmongSeveral() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-catalog-multi-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let g4   = dir.appendingPathComponent("Gemma-3-4b-it-Q4_K_M.gguf")
    let g26  = dir.appendingPathComponent("Gemma-4-26B-A4B-it-Q4_K_S.gguf")
    let p4   = dir.appendingPathComponent("mmproj-gemma-3-4b-it-f16.gguf")
    let p26  = dir.appendingPathComponent("mmproj-gemma-4-26B-A4B-f16.gguf")
    for u in [g4, g26, p4, p26] { try Data("x".utf8).write(to: u) }

    #expect(ModelCatalog.mmproj(for: g4)?.lastPathComponent == "mmproj-gemma-3-4b-it-f16.gguf")
    #expect(ModelCatalog.mmproj(for: g26)?.lastPathComponent == "mmproj-gemma-4-26B-A4B-f16.gguf")
}

@Test func mmprojNotPairedWithoutNameOverlap() throws {
    // The real post-swap layout: gemma-3-12b (no gemma projector) alongside two Qwen
    // projectors must NOT mispair; each Qwen model gets its own.
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-pair-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    for f in ["gemma-3-12b-it-Q4_K_M.gguf", "Qwen3.5-9B-UD-Q4_K_XL.gguf", "Qwen3.5-4B-UD-Q4_K_XL.gguf",
              "mmproj-Qwen3.5-9B-F16.gguf", "mmproj-Qwen3.5-4B-F16.gguf"] {
        try Data("x".utf8).write(to: dir.appendingPathComponent(f))
    }
    #expect(ModelCatalog.mmproj(for: dir.appendingPathComponent("gemma-3-12b-it-Q4_K_M.gguf")) == nil)
    #expect(ModelCatalog.mmproj(for: dir.appendingPathComponent("Qwen3.5-9B-UD-Q4_K_XL.gguf"))?.lastPathComponent == "mmproj-Qwen3.5-9B-F16.gguf")
    #expect(ModelCatalog.mmproj(for: dir.appendingPathComponent("Qwen3.5-4B-UD-Q4_K_XL.gguf"))?.lastPathComponent == "mmproj-Qwen3.5-4B-F16.gguf")
}

@Test func mmprojPairsLoneGenericProjector() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-generic-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }
    try Data("x".utf8).write(to: dir.appendingPathComponent("SomeVLM-Q4_K_M.gguf"))
    try Data("x".utf8).write(to: dir.appendingPathComponent("mmproj-model-f16.gguf"))
    #expect(ModelCatalog.mmproj(for: dir.appendingPathComponent("SomeVLM-Q4_K_M.gguf"))?.lastPathComponent == "mmproj-model-f16.gguf")
}

@Test func textOnlyModelHasNoProjector() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("slate-catalog-solo-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let m = dir.appendingPathComponent("Qwen3-Coder.gguf")
    try Data("x".utf8).write(to: m)
    #expect(ModelCatalog.mmproj(for: m) == nil)
}

@Test func chatMessageImagePathRoundTrips() throws {
    let m = ChatMessage(role: .user, content: "look", imagePath: "/tmp/x.png")
    let data = try JSONEncoder().encode(m)
    let back = try JSONDecoder().decode(ChatMessage.self, from: data)
    #expect(back.imagePath == "/tmp/x.png")
    #expect(back.content == "look")
}

@Test func chatMessageDecodesLegacyJSONWithoutImagePath() throws {
    // Conversations saved before vision existed have no imagePath key.
    let json = """
    {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","role":"assistant","content":"hello"}
    """
    let back = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(back.imagePath == nil)
    #expect(back.content == "hello")
}
