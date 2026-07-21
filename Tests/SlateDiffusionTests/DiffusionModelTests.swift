import Testing
import Foundation
@testable import SlateDiffusion

@Test func fluxModelExposesArchAndFiles() {
    let m = DiffusionModel(
        id: "flux2-klein-9b", name: "FLUX.2 klein 9B", arch: .flux2,
        diffusionPath: URL(fileURLWithPath: "/x/flux.gguf"),
        llmPath: URL(fileURLWithPath: "/x/qwen3-8b.gguf"),
        vaePath: URL(fileURLWithPath: "/x/ae.safetensors"))
    #expect(m.arch == .flux2)
    #expect(m.files.count == 3)
    #expect(m.defaultSteps == 4)
    #expect(m.defaultCfg == 1.0)
    #expect(m.defaultFlowShift == 0.0)
    #expect(m.isComplete == false)   // files don't exist
}

@Test func qwenImageDefaults() {
    let m = DiffusionModel(
        id: "qwen-image", name: "Qwen-Image", arch: .qwenImage,
        diffusionPath: URL(fileURLWithPath: "/x/qwen-image.gguf"),
        llmPath: URL(fileURLWithPath: "/x/qwen2.5-vl.gguf"),
        vaePath: URL(fileURLWithPath: "/x/qwen_vae.safetensors"))
    #expect(m.defaultSteps == 20)
    #expect(m.defaultCfg == 2.5)
    #expect(m.defaultFlowShift == 3.0)
    #expect(m.requiresReferenceImage == false)
}

@Test func editModelRequiresReferenceImage() {
    let m = DiffusionModel(
        id: "qwen-image-edit", name: "Qwen Image Edit", arch: .qwenImage,
        diffusionPath: URL(fileURLWithPath: "/x/qwen-image-edit.gguf"),
        llmPath: URL(fileURLWithPath: "/x/qwen2.5-vl.gguf"),
        vaePath: URL(fileURLWithPath: "/x/qwen_vae.safetensors"),
        requiresReferenceImage: true)
    #expect(m.requiresReferenceImage)
    #expect(m.defaultSteps == 20)
    #expect(m.defaultCfg == 2.5)
}
