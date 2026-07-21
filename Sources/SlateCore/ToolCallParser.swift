import Foundation

public struct ParsedToolCall: Equatable, Sendable {
    public let name: String
    public let arguments: [String: String]
    public init(name: String, arguments: [String: String]) {
        self.name = name; self.arguments = arguments
    }
}

/// Recognises tool calls in the several shapes local models actually emit, so agentic
/// editing works across models (not just the Hermes-JSON one):
///   1. Hermes/Qwen:  <tool_call>{ "name": …, "arguments": {…} }</tool_call>
///   2. harmony/gemma: call:NAME {loose json}      (unquoted keys tolerated)
///   3. Qwen3-Coder XML: <function=NAME><parameter=k>v</parameter></function>
public enum ToolCallParser {
    public static func containsToolCall(_ buffer: String) -> Bool {
        !parse(buffer).isEmpty
    }

    public static func parse(_ buffer: String) -> [ParsedToolCall] {
        var calls = parseHermes(buffer)
        if calls.isEmpty { calls = parseXML(buffer) }
        if calls.isEmpty { calls = parseHarmony(buffer) }
        return calls
    }

    // MARK: 1. Hermes JSON - <tool_call>{...}</tool_call>

    private static func parseHermes(_ buffer: String) -> [ParsedToolCall] {
        guard buffer.contains("<tool_call>") else { return [] }
        var calls: [ParsedToolCall] = []
        for raw in buffer.components(separatedBy: "<tool_call>").dropFirst() {
            let inner: String
            if let end = raw.range(of: "</tool_call>") { inner = String(raw[raw.startIndex..<end.lowerBound]) }
            else { inner = String(raw) }
            if let c = decodeJSON(inner) { calls.append(c) }
        }
        return calls
    }

    // MARK: 2. harmony/gemma - call:NAME {args}

    private static func parseHarmony(_ buffer: String) -> [ParsedToolCall] {
        guard let re = try? NSRegularExpression(pattern: #"\bcall\s*[:=]\s*([A-Za-z_][A-Za-z0-9_]*)"#) else { return [] }
        let ns = buffer as NSString
        var calls: [ParsedToolCall] = []
        for m in re.matches(in: buffer, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            var args: [String: String] = [:]
            let after = ns.substring(from: m.range.location + m.range.length)
            if let braced = firstBalanced(after), let obj = looseJSON(braced) {
                for (k, v) in obj { args[k] = stringify(v) }
            }
            calls.append(ParsedToolCall(name: name, arguments: args))
        }
        return calls
    }

    // MARK: 3. Qwen3-Coder XML - <function=NAME><parameter=k>v</parameter></function>

    private static func parseXML(_ buffer: String) -> [ParsedToolCall] {
        guard buffer.contains("<function=") else { return [] }
        var calls: [ParsedToolCall] = []
        for raw in buffer.components(separatedBy: "<function=").dropFirst() {
            guard let nameEnd = raw.range(of: ">") else { continue }
            let name = String(raw[raw.startIndex..<nameEnd.lowerBound])
            var args: [String: String] = [:]
            var cursor = nameEnd.upperBound
            while let pS = raw.range(of: "<parameter=", range: cursor..<raw.endIndex),
                  let pN = raw.range(of: ">", range: pS.upperBound..<raw.endIndex),
                  let pC = raw.range(of: "</parameter>", range: pN.upperBound..<raw.endIndex) {
                let key = String(raw[pS.upperBound..<pN.lowerBound])
                var val = String(raw[pN.upperBound..<pC.lowerBound])
                if val.hasPrefix("\n") { val.removeFirst() }
                if val.hasSuffix("\n") { val.removeLast() }
                args[key] = val
                cursor = pC.upperBound
            }
            calls.append(ParsedToolCall(name: name, arguments: args))
        }
        return calls
    }

    // MARK: Helpers

    private static func decodeJSON(_ json: String) -> ParsedToolCall? {
        guard let obj = looseJSON(json), let name = obj["name"] as? String else { return nil }
        var args: [String: String] = [:]
        if let a = obj["arguments"] as? [String: Any] { for (k, v) in a { args[k] = stringify(v) } }
        return ParsedToolCall(name: name, arguments: args)
    }

    /// Parse JSON, tolerating unquoted object keys (e.g. `{glob: "**/*"}`).
    static func looseJSON(_ s: String) -> [String: Any]? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = trimmed.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        let quoted = trimmed.replacingOccurrences(
            of: #"([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:"#, with: "$1\"$2\":", options: .regularExpression)
        guard let d = quoted.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    /// The first balanced `{...}` at the start of `s` (skipping leading whitespace).
    private static func firstBalanced(_ s: String) -> String? {
        let chars = Array(s)
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
        guard i < chars.count, chars[i] == "{" else { return nil }
        var depth = 0, inString = false, escaped = false
        var out = ""
        while i < chars.count {
            let c = chars[i]; out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString && c == "{" { depth += 1 }
            else if !inString && c == "}" { depth -= 1; if depth == 0 { return out } }
            i += 1
        }
        return nil
    }

    private static func stringify(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        default:
            if let d = try? JSONSerialization.data(withJSONObject: v),
               let s = String(data: d, encoding: .utf8) { return s }
            return "\(v)"
        }
    }
}
