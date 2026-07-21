import Testing
import Foundation
@testable import SlateLlama
@testable import SlateFlowCleanup
import SlateCore

/// End-to-end diagnostic for "cleanup does nothing": runs the EXACT production
/// cleanup call (CleanupPrompt → engine.generate → Reasoning.strip) against a
/// real model with the operator's failing utterance, printing raw output,
/// stripped output and timing. Gated:
///   SLATE_CLEANUP_SMOKE=1 SLATE_TEST_MODEL=~/Models/gpt-oss-20b-Q8_0.gguf \
///   SLATE_TEST_NGL=0 swift test --filter cleanupSmoke
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLATE_CLEANUP_SMOKE"] == "1"))
func cleanupSmoke() async throws {
    let modelPath = (ProcessInfo.processInfo.environment["SLATE_TEST_MODEL"]! as NSString)
        .expandingTildeInPath
    let ngl = ProcessInfo.processInfo.environment["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 0
    let engine = try LlamaEngine(modelPath: modelPath, nCtx: 4096, nGpuLayers: ngl)

    let transcript = "generiere ein bild von einem apfel äh nein doch kein apfel sondern von einer banane"
    let system = CleanupPrompt.build(style: .high, appCategory: .other, dictionary: [])
    let user = "<transcript>\(transcript)</transcript>"
    print("SMOKE system prompt chars: \(system.count)")

    let t0 = Date()
    var out = ""
    let stream = await engine.generate(
        messages: [ChatMessage(role: .system, content: system),
                   ChatMessage(role: .user, content: user)],
        grammar: nil,
        options: GenOptions(temperature: 0.2, maxTokens: 512))
    for try await piece in stream { out += piece }
    let dt = Date().timeIntervalSince(t0)

    let stripped = Reasoning.strip(out)
    print("SMOKE elapsed: \(String(format: "%.1f", dt))s")
    print("SMOKE raw chars: \(out.count)")
    print("SMOKE raw output: >>>\(out.prefix(1200))<<<")
    print("SMOKE stripped: >>>\(stripped)<<<")

    // What production would do with this result:
    let ok = !stripped.isEmpty && stripped.count <= max(80, transcript.count * 4)
    print("SMOKE production-accepts: \(ok)")
}
