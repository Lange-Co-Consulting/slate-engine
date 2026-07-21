import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SlateLlama
import SlateCore

private struct SmokeError: Error { let msg: String }

/// Writes a 256×256 PNG: a solid red circle on white. Returns its path.
private func makeRedCirclePNG() throws -> String {
    let w = 256, h = 256
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw SmokeError(msg: "context") }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 0.86, green: 0.10, blue: 0.10, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 48, y: 48, width: 160, height: 160))
    guard let img = ctx.makeImage() else { throw SmokeError(msg: "image") }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("slate-vision-\(UUID().uuidString).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw SmokeError(msg: "dest") }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw SmokeError(msg: "finalize") }
    return url.path
}

/// Real end-to-end multimodal pipeline check. Gated behind SLATE_VISION_SMOKE=1
/// and SLATE_TEST_MODEL (the VLM text GGUF); the mmproj is auto-paired from the
/// model's directory. Run:
///   SLATE_VISION_SMOKE=1 SLATE_TEST_MODEL=~/Models/Gemma-4-26B-A4B-it-Q4_K_S.gguf swift test
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLATE_VISION_SMOKE"] == "1"))
func visionDescribesImage() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["SLATE_TEST_MODEL"] else {
        throw SmokeError(msg: "SLATE_TEST_MODEL unset")
    }
    let mmproj = ModelCatalog.mmproj(for: URL(fileURLWithPath: modelPath))?.path
    #expect(mmproj != nil, "no mmproj sibling found next to the model")

    let ngl = ProcessInfo.processInfo.environment["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 999
    let ctx = ProcessInfo.processInfo.environment["SLATE_TEST_CTX"].flatMap { UInt32($0) } ?? 4096
    let engine = try LlamaEngine(modelPath: modelPath, mmprojPath: mmproj, nCtx: ctx, nGpuLayers: ngl)
    #expect(engine.isVision, "engine should report vision-capable after loading the mmproj")

    let png = try makeRedCirclePNG()
    let msg = ChatMessage(role: .user,
                          content: "What single shape is in this image and what color is it? Answer in a few words.",
                          imagePath: png)
    var output = ""
    for try await chunk in await engine.generate(messages: [msg]) {
        output += chunk
        if output.count > 400 { break }
    }
    print("=== VISION SMOKE OUTPUT ===\n\(output)\n===========================")
    #expect(!output.isEmpty)
    // Sanity (best-effort, not asserted hard): a correct VLM says "red" and "circle".
    let lc = output.lowercased()
    #expect(lc.contains("red") || lc.contains("circle"), "expected the model to mention the red circle; got: \(output)")
}
