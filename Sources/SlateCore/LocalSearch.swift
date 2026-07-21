import Foundation

public enum LocalSearch {
    /// Diacritic/case-insensitive token score. nil means not every query token
    /// occurs. Earlier and repeated matches rank higher without an index daemon.
    public static func score(query: String, in text: String) -> Int? {
        let normalizedText = normalize(text)
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        var score = 0
        for token in tokens {
            guard let first = normalizedText.range(of: token) else { return nil }
            let offset = normalizedText.distance(from: normalizedText.startIndex, to: first.lowerBound)
            let repeats = normalizedText.components(separatedBy: token).count - 1
            score += max(1, 200 - min(offset, 180)) + min(repeats, 10) * 8
        }
        return score
    }

    public static func snippet(query: String, from text: String, radius: Int = 90) -> String {
        let flat = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > radius * 2 else { return flat }
        let token = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        guard let range = flat.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flat.prefix(radius * 2)) + "…"
        }
        let offset = flat.distance(from: flat.startIndex, to: range.lowerBound)
        let startOffset = max(0, offset - radius)
        let endOffset = min(flat.count, offset + token.count + radius)
        let start = flat.index(flat.startIndex, offsetBy: startOffset)
        let end = flat.index(flat.startIndex, offsetBy: endOffset)
        return (startOffset > 0 ? "…" : "") + String(flat[start..<end]) + (endOffset < flat.count ? "…" : "")
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
