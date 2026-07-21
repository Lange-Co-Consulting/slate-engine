import Foundation

/// Zero-latency token estimate for the context dashboard. Char-based (≈ chars/3.6),
/// good enough for a live "used / window" gauge without a tokenizer round-trip.
/// Always present results as approximate (the UI prefixes "≈").
public enum TokenEstimate {
    public static func tokens(_ text: String) -> Int {
        text.isEmpty ? 0 : max(1, Int((Double(text.count) / 3.6).rounded()))
    }

    public static func tokens(_ messages: [ChatMessage]) -> Int {
        // +4 tokens per message for role/format overhead, matching common heuristics.
        messages.reduce(0) { $0 + tokens($1.content) + 4 }
    }

    /// "1.2k" / "850" compact formatting for the gauge label.
    public static func short(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }
}
