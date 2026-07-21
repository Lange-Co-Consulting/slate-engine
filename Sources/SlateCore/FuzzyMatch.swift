import Foundation

/// Subsequence fuzzy matching for the command palette / quick-switchers.
/// `score` returns nil when `query` isn't a subsequence of `candidate`, else a
/// higher-is-better score that rewards consecutive runs and word-boundary hits.
public enum FuzzyMatch {
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }            // empty query matches everything
        let c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }

        var qi = 0, total = 0, run = 0
        var prevMatchedIndex = -2
        for (ci, ch) in c.enumerated() {
            guard qi < q.count, ch == q[qi] else { continue }
            var s = 10
            if ci == prevMatchedIndex + 1 { run += 1; s += 15 * run } else { run = 0 }   // consecutive
            if ci == 0 { s += 20 }                                                        // start
            else {
                let before = c[ci - 1]
                if before == " " || before == "-" || before == "_" || before == "/" || before == "." {
                    s += 15                                                               // word boundary
                }
            }
            s -= min(ci, 10)                                                              // earlier is better
            total += s
            prevMatchedIndex = ci
            qi += 1
        }
        return qi == q.count ? total : nil
    }

    /// Rank items by fuzzy score against `query`, dropping non-matches. A blank
    /// query keeps the original order.
    public static func rank<T>(_ query: String, _ items: [T], key: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        return items
            .compactMap { item -> (T, Int)? in score(q, key(item)).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
