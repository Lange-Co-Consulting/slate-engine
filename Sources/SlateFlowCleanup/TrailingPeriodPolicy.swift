import Foundation

/// Wispr's trailing-period rule (spec item 7): short messages in chat apps end
/// without a period ("Bis gleich" not "Bis gleich."); email/code/other keep it.
public enum TrailingPeriodPolicy {
    public static func strip(_ text: String, appCategory: AppCategory, sentences: Int) -> String {
        guard appCategory == .messaging, sentences <= 2, text.hasSuffix("."),
              !text.hasSuffix("..") else { return text }
        return String(text.dropLast())
    }

    /// Rough sentence count for the policy: terminator runs, minimum 1.
    public static func sentenceCount(_ text: String) -> Int {
        let n = text.split(whereSeparator: { ".!?".contains($0) })
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        return max(1, n)
    }
}
