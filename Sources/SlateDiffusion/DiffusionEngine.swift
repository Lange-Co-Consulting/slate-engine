import Foundation
import AppKit
import ImageIO
import SlateCore
import sd

public struct ImageRequest: Sendable {
    public var prompt: String
    public var width: Int
    public var height: Int
    public var steps: Int?      // nil → model default
    public var cfg: Float?      // nil → model default
    public var seed: Int64      // -1 → random
    /// img2img: path of the source image (nil = plain txt2img).
    public var initImagePath: String?
    /// img2img only: how far to move away from the source (0 = copy, 1 = ignore).
    public var strength: Float
    public init(prompt: String, width: Int = 1024, height: Int = 1024,
                steps: Int? = nil, cfg: Float? = nil, seed: Int64 = -1,
                initImagePath: String? = nil, strength: Float = 0.6) {
        self.prompt = prompt; self.width = width; self.height = height
        self.steps = steps; self.cfg = cfg; self.seed = seed
        self.initImagePath = initImagePath; self.strength = strength
    }
}

public enum DiffusionError: Error, LocalizedError, Sendable {
    case loadFailed, notLoaded, generateFailed, invalidInput

    public var errorDescription: String? {
        switch self {
        case .loadFailed: return "The image model files are missing or invalid."
        case .notLoaded: return "No image model is loaded."
        case .generateFailed: return "The image model could not generate this image."
        case .invalidInput: return "The image request or source image is outside Slate's safe limits."
        }
    }
}

/// Progress bridge: sd.cpp's callback is a global C function pointer with no
/// captured context, so the live handler lives in a global box. Generation is
/// serialized by the actor, so only one is ever active.
private final class ProgressBox: @unchecked Sendable { var onStep: ((Int, Int) -> Void)? }
private let progressBox = ProgressBox()

public actor DiffusionEngine {
    private var ctx: OpaquePointer?          // sd_ctx_t*
    private var owned: [UnsafeMutablePointer<CChar>] = []   // strdup'd paths kept alive with ctx
    public private(set) var loaded: DiffusionModel?

    public init() {}

    public var isLoaded: Bool { ctx != nil }

    public func load(_ model: DiffusionModel) throws {
        guard model.files.allSatisfy(Self.isSafeModelFile) else { throw DiffusionError.loadFailed }
        unload()
        var p = sd_ctx_params_t()
        sd_ctx_params_init(&p)
        func keep(_ s: String) -> UnsafePointer<CChar> {
            let d = strdup(s)!; owned.append(d); return UnsafePointer(d)
        }
        p.diffusion_model_path = keep(model.diffusionPath.path)
        p.llm_path = keep(model.llmPath.path)
        p.vae_path = keep(model.vaePath.path)
        p.diffusion_flash_attn = true
        p.flash_attn = true
        // CRITICAL on 24GB unified memory: keep ALL weights in CPU RAM and stream
        // to the GPU per-op (= the CLI's --offload-to-cpu). Without this, sd.cpp
        // loads the 9GB diffusion + 8GB encoder into the ~19GB Metal working set
        // and aborts (ggml_abort) mid text-encode. "*=cpu" → every module's params
        // live on CPU; compute still runs on Metal.
        p.params_backend = keep("*=cpu")
        guard let c = new_sd_ctx(&p) else { freeOwned(); throw DiffusionError.loadFailed }
        ctx = c
        loaded = model
    }

    public func unload() {
        if let c = ctx { free_sd_ctx(c); ctx = nil }
        loaded = nil
        freeOwned()
    }

    private func freeOwned() { owned.forEach { free($0) }; owned = [] }

    public func generate(_ req: ImageRequest, onStep: @escaping @Sendable (Int, Int) -> Void) throws -> Data {
        guard let c = ctx, let model = loaded else { throw DiffusionError.notLoaded }
        guard (64...2_048).contains(req.width), (64...2_048).contains(req.height),
              req.width % 64 == 0, req.height % 64 == 0,
              req.prompt.utf8.count <= 16_000,
              req.steps.map({ (1...100).contains($0) }) ?? true,
              req.cfg.map({ $0.isFinite && (0...30).contains($0) }) ?? true,
              req.strength.isFinite && (0...1).contains(req.strength) else {
            throw DiffusionError.invalidInput
        }

        progressBox.onStep = onStep
        sd_set_progress_callback({ step, steps, _, _ in
            progressBox.onStep?(Int(step), Int(steps))
        }, nil)
        defer { progressBox.onStep = nil }

        var g = sd_img_gen_params_t()
        sd_img_gen_params_init(&g)
        let prompt = strdup(req.prompt)!
        defer { free(prompt) }
        g.prompt = UnsafePointer(prompt)
        g.width = Int32(req.width)
        g.height = Int32(req.height)
        g.seed = req.seed
        g.batch_count = 1
        g.sample_params.sample_steps = Int32(req.steps ?? model.defaultSteps)
        g.sample_params.guidance.txt_cfg = req.cfg ?? model.defaultCfg
        g.sample_params.flow_shift = model.defaultFlowShift
        g.sample_params.sample_method = str_to_sample_method("euler")

        // img2img: aspect-fill the source into the target frame as packed RGB8.
        var initBuf: UnsafeMutablePointer<UInt8>?
        defer { if let b = initBuf { free(b) } }
        if let srcPath = req.initImagePath {
            guard Self.isSafeInputImage(path: srcPath) else { throw DiffusionError.invalidInput }
            guard let buf = Self.rgb8(path: srcPath, width: req.width, height: req.height) else {
                throw DiffusionError.generateFailed
            }
            initBuf = buf
            g.init_image = sd_image_t(width: UInt32(req.width), height: UInt32(req.height),
                                      channel: 3, data: buf)
            g.strength = req.strength
        }

        var out: UnsafeMutablePointer<sd_image_t>?
        var n: Int32 = 0
        let ok = generate_image(c, &g, &out, &n)
        guard ok, let images = out, n > 0 else { throw DiffusionError.generateFailed }
        defer {
            for i in 0..<Int(n) { free(images[i].data) }
            free(images)
        }
        return try Self.png(from: images[0])
    }

    /// Any image file → packed RGB8 at exactly width×height (aspect-fill,
    /// center-cropped). malloc'd - caller frees. Uses the same NSBitmapImageRep
    /// memory layout the OUTPUT path relies on (row 0 = top).
    private static func rgb8(path: String, width w: Int, height h: Int) -> UnsafeMutablePointer<UInt8>? {
        guard let src = NSImage(contentsOfFile: path),
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: w * 4, bitsPerPixel: 32),
              let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        gctx.imageInterpolation = .high
        let srcSize = src.size
        let srcAspect = srcSize.width / max(srcSize.height, 1)
        let dstAspect = CGFloat(w) / CGFloat(h)
        let r: NSRect
        if srcAspect > dstAspect {
            let dw = CGFloat(h) * srcAspect
            r = NSRect(x: (CGFloat(w) - dw) / 2, y: 0, width: dw, height: CGFloat(h))
        } else {
            let dh = CGFloat(w) / srcAspect
            r = NSRect(x: 0, y: (CGFloat(h) - dh) / 2, width: CGFloat(w), height: dh)
        }
        src.draw(in: r, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let rgba = rep.bitmapData, let raw = malloc(w * h * 3) else { return nil }
        let out = raw.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(w * h) {
            out[i * 3] = rgba[i * 4]
            out[i * 3 + 1] = rgba[i * 4 + 1]
            out[i * 3 + 2] = rgba[i * 4 + 2]
        }
        return out
    }

    private static func isSafeModelFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "gguf": return DownloadCatalog.hasGGUFMagic(url)
        case "safetensors": return DownloadCatalog.hasSafeTensorsHeader(url)
        default: return false
        }
    }

    private static func isSafeInputImage(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...50 * 1_024 * 1_024).contains(size),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000_000 / height else { return false }
        return true
    }

    /// sd_image_t (packed RGB, 8-bit, channel==3) → PNG bytes.
    private static func png(from img: sd_image_t) throws -> Data {
        let w = Int(img.width), h = Int(img.height), ch = Int(img.channel)
        guard let data = img.data, ch == 3 || ch == 4 else { throw DiffusionError.generateFailed }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: ch, hasAlpha: ch == 4,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: w * ch, bitsPerPixel: ch * 8),
              let dst = rep.bitmapData else { throw DiffusionError.generateFailed }
        memcpy(dst, data, w * h * ch)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw DiffusionError.generateFailed }
        return png
    }
}
