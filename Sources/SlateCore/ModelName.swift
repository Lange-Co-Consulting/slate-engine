import Foundation

/// Turns a raw model filename into a short, human display name.
///
/// Model files conventionally lead with the meaningful part —
/// `Family Version Size` — and trail with noise: fine-tune/variant markers
/// (`Instruct`, `abliterated`, `uncensored`), uploader/runtime tags, quant
/// (`Q4_K_M`, `IQ3_M`) and the file format (`gguf`). This keeps the leading
/// meaningful tokens and truncates at the first noise token, so
/// `Gemma-4-12b-abliterated-gguf-Q4_K_M.gguf` becomes `Gemma 4 12B` and
/// `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf` becomes `Qwen3.6 27B`.
public enum ModelName {
    /// Whole-token markers (case-insensitive) that begin the droppable tail.
    private static let noiseWords: Set<String> = [
        "instruct", "instruction", "chat", "it", "base",
        "sft", "dpo", "rlhf", "rl", "kto", "orpo",
        "abliterated", "ablit", "uncensored", "aggressive", "neo",
        "distill", "distilled", "distillation",
        "merge", "merged", "unsloth", "hf", "mlx", "ct2", "awq", "gptq",
        "gguf", "ggml", "safetensors", "bin", "pt", "pth",
        "f16", "f32", "bf16", "fp16", "fp32", "int8", "int4", "8bit", "4bit",
    ]

    private static func isNoise(_ token: String) -> Bool {
        let t = token.lowercased()
        if noiseWords.contains(t) { return true }
        // Quant tokens: Q4_K_M, IQ3_M, Q2_K_XL, Q8_0, UD-Q2… (leading Q/IQ + digit).
        return t.range(of: "^i?q[0-9]", options: .regularExpression) != nil
    }

    /// `12b` → `12B`, `270m` → `270M`, `a3b` → `A3B`; anything else is untouched.
    private static func normalizeSize(_ token: String) -> String {
        if token.range(of: "^[aA]?[0-9]+(\\.[0-9]+)?[bmBM]$", options: .regularExpression) != nil {
            return token.uppercased()
        }
        return token
    }

    /// The disambiguating tail `pretty()` deliberately drops: quantisation, revision and
    /// fine-tune variant. `Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf` → "Q4_K_M · Instruct 2507".
    /// "" when the name carries nothing distinguishing. Two files that prettify identically
    /// are otherwise indistinguishable in every picker in the app.
    public static func qualifier(_ raw: String) -> String {
        var base = raw
        for ext in [".gguf", ".ggml", ".safetensors", ".bin", ".pt", ".pth"] where base.lowercased().hasSuffix(ext) {
            base = String(base.dropLast(ext.count)); break
        }
        // Split on '-' and space only — NOT '_', so a quant like Q4_K_M stays one token.
        let tokens = base.split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init)
        var start: Int? = nil
        var keptAny = false
        for (i, token) in tokens.enumerated() {
            if isNoise(token) {
                if !keptAny { continue }       // pretty() skips a LEADING noise token
                start = i; break
            }
            keptAny = true
        }
        guard let from = start else { return "" }
        let formats: Set<String> = ["gguf", "ggml", "safetensors", "bin", "pt", "pth"]
        var quant: [String] = []
        var rest: [String] = []
        for token in tokens[from...] {
            let t = token.lowercased()
            if formats.contains(t) { continue }
            if t.range(of: "^i?q[0-9]", options: .regularExpression) != nil
                || ["f16", "bf16", "f32", "fp16", "fp32", "int8", "int4"].contains(t) {
                quant.append(token.uppercased())
            } else {
                rest.append(token.prefix(1).uppercased() + token.dropFirst())
            }
        }
        let tail = quant + (rest.isEmpty ? [] : [rest.joined(separator: " ")])
        return tail.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public static func pretty(_ raw: String) -> String {
        // Drop a trailing model-file extension.
        var base = raw
        for ext in [".gguf", ".ggml", ".safetensors", ".bin", ".pt", ".pth"] where base.lowercased().hasSuffix(ext) {
            base = String(base.dropLast(ext.count)); break
        }
        // Split on -, _ and whitespace — NOT '.', so versions like 2.5 survive.
        let tokens = base.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map(String.init)
        var kept: [String] = []
        for token in tokens {
            if isNoise(token) {
                if kept.isEmpty { continue }   // skip a leading noise token, never end empty
                break                          // otherwise the meaningful part is over
            }
            kept.append(normalizeSize(token))
        }
        if kept.isEmpty { kept = tokens.map(normalizeSize) }   // all-noise fallback
        var result = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        // Capitalize a lowercase family name (gemma → Gemma); leave GPT/Qwen alone.
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }
        return result.isEmpty ? raw : result
    }
}
