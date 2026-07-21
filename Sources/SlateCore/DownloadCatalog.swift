import Foundation

/// A curated, download-ready model (exact HF resolve URL). `bytes` is the known
/// size for display and RAM guidance; the downloader verifies the real remote
/// Content-Length and the GGUF magic after transfer, so a stale catalog size can
/// never corrupt an install.
public struct CatalogModel: Sendable, Identifiable, Equatable {
    public let name: String
    public let detail: String
    public let fileName: String
    public let urlString: String
    public let bytes: Int64
    public let licenseName: String
    public let licenseURLString: String
    public var id: String { fileName }
    public var url: URL? { URL(string: urlString) }
    public var licenseURL: URL? { URL(string: licenseURLString) }
    public var modelCardURL: URL? {
        guard let marker = urlString.range(of: "/resolve/") else { return nil }
        return URL(string: String(urlString[..<marker.lowerBound]))
    }

    public init(name: String, detail: String, fileName: String, urlString: String, bytes: Int64,
                licenseName: String, licenseURLString: String) {
        self.name = name; self.detail = detail; self.fileName = fileName
        self.urlString = urlString; self.bytes = bytes
        self.licenseName = licenseName; self.licenseURLString = licenseURLString
    }
}

/// How comfortably a model file fits the machine's RAM (weights are memory-mapped
/// and must stay resident; KV cache and the app need headroom on top).
public enum ModelRAMFit: Sendable {
    case comfortable   // ≤ 60% of physical RAM
    case tight         // ≤ 80% - works, but starves the KV cache / other apps
    case tooBig        // > 80% - likely to OOM or page

    public static func evaluate(fileBytes: Int64, physicalRAM: UInt64) -> ModelRAMFit {
        guard physicalRAM > 0 else { return .tooBig }
        let frac = Double(fileBytes) / Double(physicalRAM)
        if frac <= 0.60 { return .comfortable }
        if frac <= 0.80 { return .tight }
        return .tooBig
    }
}

public enum DownloadCatalog {
    /// Curated set matching Slate's roles: coding agent, fast fallback, German
    /// business/legal chat, EU-sovereign alternative. Sizes verified 2026-07.
    public static let models: [CatalogModel] = [
        CatalogModel(
            name: "Qwen3.5 35B A3B (IQ4_XS)",
            detail: "Coding agent - MoE, strong tools & reasoning",
            fileName: "Qwen3.5-35B-A3B-UD-IQ4_XS.gguf",
            urlString: "https://huggingface.co/unsloth/Qwen3.5-35B-A3B-GGUF/resolve/main/Qwen3.5-35B-A3B-UD-IQ4_XS.gguf",
            bytes: 17_486_174_848,
            licenseName: "Apache-2.0",
            licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0"),
        CatalogModel(
            name: "Qwen3.5 9B (Q4_K_XL)",
            detail: "Fast fallback & subagents",
            fileName: "Qwen3.5-9B-UD-Q4_K_XL.gguf",
            urlString: "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-UD-Q4_K_XL.gguf",
            bytes: 5_966_095_584,
            licenseName: "Apache-2.0",
            licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0"),
        CatalogModel(
            name: "SauerkrautLM 14B v2 (Q5_K_M)",
            detail: "German business/legal chat - native DE tuning",
            fileName: "SauerkrautLM-v2-14b-DPO.Q5_K_M.gguf",
            urlString: "https://huggingface.co/mradermacher/SauerkrautLM-v2-14b-DPO-GGUF/resolve/main/SauerkrautLM-v2-14b-DPO.Q5_K_M.gguf",
            bytes: 10_508_872_416,
            licenseName: "Apache-2.0",
            licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0"),
        CatalogModel(
            name: "EuroLLM 9B Instruct (Q6_K)",
            detail: "EU-built, all 24 EU languages, Apache 2.0",
            fileName: "EuroLLM-9B-Instruct-Q6_K.gguf",
            urlString: "https://huggingface.co/bartowski/EuroLLM-9B-Instruct-GGUF/resolve/main/EuroLLM-9B-Instruct-Q6_K.gguf",
            bytes: 7_511_956_192,
            licenseName: "Apache-2.0",
            licenseURLString: "https://www.apache.org/licenses/LICENSE-2.0"),
    ]

    /// The canonical install directory for downloads.
    public static func installDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models", isDirectory: true)
    }

    /// Total resource size out of an HTTP 206 `Content-Range: bytes A-B/TOTAL`
    /// header. Returns nil for a missing header or an unknown ("*") total.
    ///
    /// This matters because a RESUMED download reports `expectedContentLength` as
    /// the REMAINING bytes, not the full file - so the full size must come from
    /// Content-Range (or a known catalog size) to verify a stitched file correctly.
    public static func totalBytes(fromContentRange header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        let total = header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Int64(total)   // "*" or empty → nil
    }

    /// True when the first four bytes of the file are the GGUF magic.
    public static func hasGGUFMagic(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) >= 4 else { return false }
        guard let h = try? FileHandle(forReadingFrom: url),
              let data = try? h.read(upToCount: 4) else { return false }
        try? h.close()
        return data == Data("GGUF".utf8)
    }

    /// Basic safetensors envelope validation. This is not a cryptographic
    /// signature, but it rejects directories, links, truncated files and random
    /// data before a native model loader receives the file.
    public static func hasSafeTensorsHeader(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 10 else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return false }
        var headerLength: UInt64 = 0
        for (index, byte) in prefix.enumerated() {
            headerLength |= UInt64(byte) << UInt64(index * 8)
        }
        let maximumHeader: UInt64 = 1_024 * 1_024
        guard headerLength >= 2, headerLength <= maximumHeader,
              headerLength <= UInt64(size - 8),
              let header = try? handle.read(upToCount: Int(headerLength)),
              header.count == Int(headerLength),
              (try? JSONSerialization.jsonObject(with: header)) is [String: Any] else { return false }
        return true
    }
}
