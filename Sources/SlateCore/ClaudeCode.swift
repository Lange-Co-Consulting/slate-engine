import Foundation

/// Piggyback bridge to the `claude` CLI (Claude Code) in headless stream-json mode.
/// Pure request-building + line parsing here (unit-tested); the Process lives in the
/// app. This is Slate's optional CLOUD engine: it inherits whatever auth `claude`
/// is logged into - a Claude subscription runs over normal usage (no API credits);
/// only an API-key login bills credits.
public enum ClaudeCode {
    /// How Slate's permission mode maps onto Claude Code's headless flags.
    public static func permissionArgs(_ mode: PermissionMode,
                                      skipPermissions: Bool = false) -> [String] {
        switch mode {
        case .autopilot where skipPermissions:
            return ["--dangerously-skip-permissions"]
        case .autopilot:
            // Claude Code's native Auto classifier decides which operations
            // still need review. This is distinct from bypassPermissions.
            return ["--permission-mode", "auto"]
        case .acceptEdits: return ["--permission-mode", "acceptEdits"]
        case .ask:         return ["--permission-mode", "default"]
        }
    }

    /// Argument vector for a headless streaming turn. The prompt itself is fed on
    /// stdin (avoids all shell/arg escaping), so it is NOT in here. We parse whole
    /// assistant blocks (works on every CLI version) rather than partial-message
    /// deltas, so no `--include-partial-messages` dependency.
    public static func arguments(sessionId: String?, mode: PermissionMode, addDir: String?,
                                 skipPermissions: Bool = false, model: String? = nil,
                                 appendSystemPrompt: String? = nil, webSearch: Bool = false) -> [String] {
        var a = ["--print",
                 "--output-format", "stream-json",
                 "--verbose",
                 // Do not load project/user hooks, MCP servers or plugins into
                 // a headless agent turn. Built-in tools and permissions remain.
                 "--safe-mode",
                 // Defense in depth for Claude's own Bash tool. These remain
                 // denied even when the global Skip permissions latch is on.
                 "--disallowedTools",
                 "Bash(rm *)", "Bash(rmdir *)", "Bash(unlink *)", "Bash(shred *)",
                 "Bash(mv *)", "Bash(find *)", "Bash(truncate *)",
                 "Bash(sudo *)", "Bash(git clean *)", "Bash(git reset --hard*)",
                 "Bash(git restore *)", "Bash(git checkout -- *)",
                 "Bash(curl *)", "Bash(wget *)", "Bash(nc *)", "Bash(scp *)", "Bash(ssh *)",
                 "Bash(kill *)", "Bash(killall *)", "Bash(pkill *)"]
        // WebSearch/WebFetch stay disallowed unless the user opts in for this turn
        // (offline-first; forced off in Silent Mode).
        if !webSearch { a += ["WebSearch", "WebFetch"] }
        a += permissionArgs(mode, skipPermissions: skipPermissions)
        if let sessionId, !sessionId.isEmpty { a += ["--resume", sessionId] }
        if let addDir, !addDir.isEmpty { a += ["--add-dir", addDir] }
        if let model, !model.isEmpty { a += ["--model", model] }
        if let sp = appendSystemPrompt, !sp.isEmpty { a += ["--append-system-prompt", sp] }
        return a
    }

    /// One parsed stream-json line.
    public enum Event: Equatable, Sendable {
        case sessionStarted(String)          // system/init → session_id (store for --resume)
        case thinking(String)                // extended-thinking text (shown collapsibly)
        case textDelta(String)               // assistant answer text
        case toolUse(String)                 // "⚙ Edit path" activity line
        case toolResult(String)              // "↳ output…" (truncated)
        case result(text: String?, isError: Bool, costUSD: Double?, turns: Int?)   // final summary
        case ignored
    }

    /// Parse a single JSONL line from `--output-format stream-json`. One line can
    /// carry several events (an assistant message may hold text + tool-use blocks).
    public static func parse(_ line: String) -> [Event] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else { return [] }

        switch type {
        case "system":
            if obj["subtype"] as? String == "init", let sid = obj["session_id"] as? String {
                return [.sessionStarted(sid)]
            }
            return []

        case "stream_event":   // partial deltas (only if the CLI emits them)
            if let ev = obj["event"] as? [String: Any],
               ev["type"] as? String == "content_block_delta",
               let delta = ev["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return [.textDelta(text)]
            }
            return []

        case "assistant":      // whole message: thinking / text / tool_use blocks
            guard let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return [] }
            var events: [Event] = []
            for block in content {
                switch block["type"] as? String {
                case "thinking":
                    if let t = block["thinking"] as? String, !t.isEmpty { events.append(.thinking(t)) }
                case "text":
                    if let t = block["text"] as? String, !t.isEmpty { events.append(.textDelta(t)) }
                case "tool_use":
                    events.append(.toolUse(toolSummary(name: block["name"] as? String ?? "tool",
                                                       input: block["input"] as? [String: Any])))
                default: break
                }
            }
            return events

        case "user":           // tool results are fed back as user messages
            guard let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { block in
                block["type"] as? String == "tool_result"
                    ? .toolResult(toolResultSummary(block["content"])) : nil
            }

        case "result":
            let text = obj["result"] as? String
            let isError = (obj["is_error"] as? Bool) ?? (obj["subtype"] as? String)?.hasPrefix("error") ?? false
            let cost = obj["total_cost_usd"] as? Double
            let turns = obj["num_turns"] as? Int
            return [.result(text: text, isError: isError, costUSD: cost, turns: turns)]

        default:
            return []
        }
    }

    /// A short one-line summary of a tool_result's content (string or block array).
    static func toolResultSummary(_ content: Any?) -> String {
        var text = ""
        if let s = content as? String { text = s }
        else if let arr = content as? [[String: Any]] {
            text = arr.compactMap { $0["text"] as? String }.joined(separator: " ")
        }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return "↳ " + (trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed)
    }

    /// "⚙ Edit src/foo.swift" - a readable one-liner for a tool call.
    static func toolSummary(name: String, input: [String: Any]?) -> String {
        let target = (input?["file_path"] as? String)
            ?? (input?["path"] as? String)
            ?? (input?["command"] as? String)
            ?? (input?["pattern"] as? String)
            ?? (input?["url"] as? String)
            ?? ""
        let short = target.count > 80 ? String(target.suffix(80)) : target
        return short.isEmpty ? "⚙ \(name)" : "⚙ \(name)  \(short)"
    }
}
