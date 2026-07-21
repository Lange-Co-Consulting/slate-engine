import Foundation

/// A local diffusion model as a set of on-disk files. sd.cpp takes the diffusion
/// transformer, a text encoder (`--llm`: Qwen3 for FLUX.2-klein, Qwen2.5-VL for
/// Qwen-Image) and a VAE - the same three roles for both architectures.
public struct DiffusionModel: Sendable, Equatable, Identifiable {
    public enum Arch: String, Sendable, Codable { case flux2, qwenImage }

    public let id: String
    public let name: String
    public let arch: Arch
    public let diffusionPath: URL
    public let llmPath: URL     // text encoder
    public let vaePath: URL
    /// Some image models are only meaningful with a source image (img2img).
    public let requiresReferenceImage: Bool

    public init(id: String, name: String, arch: Arch,
                diffusionPath: URL, llmPath: URL, vaePath: URL,
                requiresReferenceImage: Bool = false) {
        self.id = id; self.name = name; self.arch = arch
        self.diffusionPath = diffusionPath; self.llmPath = llmPath; self.vaePath = vaePath
        self.requiresReferenceImage = requiresReferenceImage
    }

    public var files: [URL] { [diffusionPath, llmPath, vaePath] }
    public var isComplete: Bool { files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }

    // Per-architecture sampling defaults (from stable-diffusion.cpp's model docs).
    public var defaultSteps: Int { arch == .flux2 ? 4 : 20 }
    public var defaultCfg: Float { arch == .flux2 ? 1.0 : 2.5 }
    public var defaultFlowShift: Float { arch == .qwenImage ? 3.0 : 0.0 }
}
