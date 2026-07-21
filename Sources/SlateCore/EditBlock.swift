import Foundation

public struct EditBlock: Equatable, Sendable {
    public var path: String
    public var search: String
    public var replace: String
    public init(path: String, search: String, replace: String) {
        self.path = path; self.search = search; self.replace = replace
    }
}

public enum EditBlockParser {
    private static func isHead(_ l: String) -> Bool { l.range(of: #"^<{5,9}\s*SEARCH\s*$"#, options: .regularExpression) != nil }
    private static func isMid(_ l: String)  -> Bool { l.range(of: #"^={5,9}\s*$"#, options: .regularExpression) != nil }
    private static func isTail(_ l: String) -> Bool { l.range(of: #"^>{5,9}\s*REPLACE\s*$"#, options: .regularExpression) != nil }
    private static func isFence(_ l: String) -> Bool { l.hasPrefix("```") }

    public static func parse(_ text: String) -> [EditBlock] {
        var blocks: [EditBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var lastPath = ""
        var pendingPath = ""

        while i < lines.count {
            let line = lines[i]
            if isHead(line) {
                var search: [String] = []
                i += 1
                while i < lines.count, !isMid(lines[i]) { search.append(lines[i]); i += 1 }
                guard i < lines.count else { break }
                i += 1 // skip mid
                var replace: [String] = []
                while i < lines.count, !isTail(lines[i]) { replace.append(lines[i]); i += 1 }
                let path = pendingPath.isEmpty ? lastPath : pendingPath
                lastPath = path
                pendingPath = ""
                blocks.append(EditBlock(path: path,
                                        search: search.joined(separator: "\n"),
                                        replace: replace.joined(separator: "\n")))
            } else if !isFence(line), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingPath = line.trimmingCharacters(in: .whitespaces)
            }
            i += 1
        }
        return blocks
    }
}
