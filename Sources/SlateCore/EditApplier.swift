import Foundation

public enum EditTier: Sendable, Equatable { case exact, wsNorm, fuzzy, create }

public struct EditApplyResult: Sendable, Equatable {
    public let text: String
    public let tier: EditTier
}

public enum EditApplier {
    /// Apply one block to a buffer. Cascade: create → exact → whitespace-normalized → fuzzy(≥0.85).
    public static func applyToBuffer(_ buffer: String, block: EditBlock) -> EditApplyResult? {
        let search = normalizeEOL(block.search)
        let replace = normalizeEOL(block.replace)
        let buf = normalizeEOL(buffer)

        if search.isEmpty {
            let merged = buf.isEmpty ? replace : replace + "\n" + buf
            return EditApplyResult(text: merged, tier: .create)
        }
        if let range = buf.range(of: search) {
            return EditApplyResult(text: buf.replacingCharacters(in: range, with: replace), tier: .exact)
        }
        if let result = applyWhitespaceNormalized(buf: buf, search: search, replace: replace) {
            return EditApplyResult(text: result, tier: .wsNorm)
        }
        if let result = applyFuzzy(buf: buf, search: search, replace: replace, threshold: 0.85) {
            return EditApplyResult(text: result, tier: .fuzzy)
        }
        return nil
    }

    static func normalizeEOL(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func collapseWS(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func applyWhitespaceNormalized(buf: String, search: String, replace: String) -> String? {
        let bufLines = buf.components(separatedBy: "\n")
        let searchLines = search.components(separatedBy: "\n")
        let needle = searchLines.map { collapseWS($0) }
        guard !needle.isEmpty else { return nil }
        let n = bufLines.count, m = needle.count
        guard m <= n else { return nil }
        for start in 0...(n - m) {
            var ok = true
            for j in 0..<m where collapseWS(bufLines[start + j]) != needle[j] { ok = false; break }
            if ok {
                var out = bufLines
                out.replaceSubrange(start..<(start + m), with: replace.components(separatedBy: "\n"))
                return out.joined(separator: "\n")
            }
        }
        return nil
    }

    private static func applyFuzzy(buf: String, search: String, replace: String, threshold: Double) -> String? {
        let bufLines = buf.components(separatedBy: "\n")
        let searchLines = search.components(separatedBy: "\n")
        let m = searchLines.count
        guard m >= 1, bufLines.count >= m else { return nil }
        var best: (start: Int, ratio: Double)? = nil
        for start in 0...(bufLines.count - m) {
            let window = Array(bufLines[start..<(start + m)]).joined(separator: "\n")
            let ratio = similarity(window, search)
            if best == nil || ratio > best!.ratio { best = (start, ratio) }
        }
        guard let best, best.ratio >= threshold else { return nil }
        var out = bufLines
        out.replaceSubrange(best.start..<(best.start + m), with: replace.components(separatedBy: "\n"))
        return out.joined(separator: "\n")
    }

    /// Character-level similarity (longest-common-subsequence based, 0...1).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = [Int](repeating: 0, count: y.count + 1)
        var cur = prev
        for i in 1...x.count {
            for j in 1...y.count {
                cur[j] = x[i-1] == y[j-1] ? prev[j-1] + 1 : max(prev[j], cur[j-1])
            }
            swap(&prev, &cur)
        }
        let lcs = prev[y.count]
        return (2.0 * Double(lcs)) / Double(x.count + y.count)
    }
}
