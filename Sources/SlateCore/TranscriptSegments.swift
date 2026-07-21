import Foundation

/// One ⚙/↳ line inside a tool-activity block.
public struct ToolLine: Equatable, Sendable {
    public enum Kind: Sendable { case call, result }
    public let kind: Kind
    public let text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

/// Splits a rendered answer into prose / fenced code / tool-activity segments.
/// Tool lines are exactly what the engines emit: a line that IS a backticked
/// `⚙ …` (call) or `↳ …` (result) - nothing else matches, so user prose with
/// inline backticks can't false-positive.
public enum TranscriptSegments {
    public enum Segment: Equatable, Sendable {
        case prose(String)
        case code(language: String, code: String)
        case toolActivity([ToolLine])
    }

    public static func parse(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var prose: [String] = [], tools: [ToolLine] = []
        var inCode = false, codeLang = "", code: [String] = []
        func flushProse() {
            let s = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !s.isEmpty { out.append(.prose(s)) }
            prose.removeAll()
        }
        func flushTools() {
            if !tools.isEmpty { out.append(.toolActivity(tools)); tools.removeAll() }
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    out.append(.code(language: codeLang, code: code.joined(separator: "\n")))
                    code.removeAll(); inCode = false; codeLang = ""
                } else {
                    flushProse(); flushTools()
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            } else if inCode {
                code.append(line)
            } else if let tool = toolLine(line) {
                flushProse(); tools.append(tool)
            } else {
                flushTools(); prose.append(line)
            }
        }
        if inCode { out.append(.code(language: codeLang, code: code.joined(separator: "\n"))) }
        flushProse(); flushTools()
        return out.isEmpty ? [.prose(text)] : out
    }

    /// A tool line is the WHOLE line wrapped in backticks with a ⚙/↳ payload.
    private static func toolLine(_ raw: String) -> ToolLine? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.count > 2, t.hasPrefix("`"), t.hasSuffix("`") else { return nil }
        let inner = String(t.dropFirst().dropLast())
        if inner.hasPrefix("⚙ ") { return ToolLine(kind: .call, text: String(inner.dropFirst(2))) }
        if inner.hasPrefix("↳ ") { return ToolLine(kind: .result, text: String(inner.dropFirst(2))) }
        return nil
    }
}
