import Testing
import Foundation
@testable import SlateLlama
import SlateCore

private func modelPath() -> String? {
    ProcessInfo.processInfo.environment["SLATE_TEST_MODEL"]
}

@Test func loadsAndStreamsTokens() async throws {
    guard let path = modelPath() else {
        // No model available: skip. Set SLATE_TEST_MODEL to a GGUF to run.
        return
    }
    // On a 24GB Mac the dense 18GB R1 fully GPU-offloaded exceeds the ~19GB
    // Metal working set. Use SLATE_TEST_NGL to offload fewer layers to the GPU
    // (rest on CPU) so the pipeline fits. Default 999 = full offload.
    let ngl = ProcessInfo.processInfo.environment["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 999
    let engine = try LlamaEngine(modelPath: path, nCtx: 2048, nGpuLayers: ngl)
    let messages = [ChatMessage(role: .user, content: "Say the single word: ping")]
    var output = ""
    for try await chunk in await engine.generate(messages: messages) {
        output += chunk
        if output.count > 64 { break }
    }
    #expect(!output.isEmpty)
}

@Test func badPathThrows() {
    #expect(throws: GenerationError.self) {
        _ = try LlamaEngine(modelPath: "/nonexistent/model.gguf", nCtx: 512)
    }
}
