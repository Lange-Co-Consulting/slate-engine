import Foundation

public enum DiffLine: Equatable, Sendable {
    case context(String)
    case added(String)
    case removed(String)
}

public enum LineDiff {
    /// Line-level diff via longest-common-subsequence backtracking.
    public static func compute(old: String, new: String) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let n = a.count, m = b.count
        guard n > 0 || m > 0 else { return [] }

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { result.append(.context(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { result.append(.removed(a[i])); i += 1 }
            else { result.append(.added(b[j])); j += 1 }
        }
        while i < n { result.append(.removed(a[i])); i += 1 }
        while j < m { result.append(.added(b[j])); j += 1 }
        return result
    }

    /// A "+/-/ " prefixed rendering (capped) for previews.
    public static func unified(old: String, new: String, maxLines: Int = 500) -> String {
        compute(old: old, new: new).prefix(maxLines).map { line in
            switch line {
            case .context(let s): return "  " + s
            case .added(let s): return "+ " + s
            case .removed(let s): return "- " + s
            }
        }.joined(separator: "\n")
    }

    /// Counts of added / removed lines (for a summary).
    public static func stats(old: String, new: String) -> (added: Int, removed: Int) {
        var add = 0, rem = 0
        for line in compute(old: old, new: new) {
            switch line { case .added: add += 1; case .removed: rem += 1; case .context: break }
        }
        return (add, rem)
    }
}
