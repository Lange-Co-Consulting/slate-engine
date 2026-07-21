import Foundation

/// Decides how much of the KV cache can be reused between generation calls.
///
/// The engine tracks which tokens are currently materialized in the KV cache
/// (`previous` = fed prompt tokens + generated tokens). For the next prompt
/// (`next`), everything up to the first divergence can stay; only the suffix
/// must be decoded. We always re-feed at least the final token so the decode
/// leaves fresh logits to sample from - llama.cpp needs ≥1 new token per call.
public enum PromptCache {
    public struct Plan: Equatable {
        /// Tokens to keep in the KV cache (positions 0..<keep survive).
        public let keep: Int
        /// Range of `next` that must be fed to the model.
        public let feed: Range<Int>
    }

    public static func plan(previous: [Int32], next: [Int32]) -> Plan {
        guard !next.isEmpty else { return Plan(keep: 0, feed: 0..<0) }
        var common = 0
        let limit = min(previous.count, next.count)
        while common < limit && previous[common] == next[common] { common += 1 }
        // Never keep the entire next prompt: re-feed the last token for fresh logits.
        let keep = min(common, next.count - 1)
        return Plan(keep: keep, feed: keep..<next.count)
    }
}
