import Testing
import Foundation
@testable import SlateCore

@Test func findsGgufFilesUnderDirectories() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("slate-mc-\(UUID().uuidString)")
    let sub = base.appendingPathComponent("deepseek")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data().write(to: sub.appendingPathComponent("model-Q4_K_M.gguf"))
    try Data().write(to: base.appendingPathComponent("notes.txt"))
    let models = ModelCatalog.scan(directories: [base])
    #expect(models.map(\.name).contains("model-Q4_K_M.gguf"))
    #expect(models.allSatisfy { $0.url.pathExtension == "gguf" })
}
