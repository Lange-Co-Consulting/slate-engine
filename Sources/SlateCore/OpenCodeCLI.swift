import Foundation

/// Pure helpers for OpenCode's headless JSON CLI. The Process wrapper lives in
/// SlateApp; keeping parsing/argument construction here makes the integration
/// deterministic and unit-testable without spending provider tokens.
public enum OpenCodeCLI {
    public enum Event: Equatable, Sendable {
        case sessionStarted(String)
        case text(String)
        case reasoning(String)
        case tool(String)
        case finished(totalTokens: Int?, cost: Double?)
        case ignored
    }

    public static func arguments(model: String, sessionID: String?, directory: String,
                                 skipPermissions: Bool) -> [String] {
        var args = ["run", "--pure", "--format", "json", "--model", model,
                    "--dir", directory, "--thinking"]
        if let sessionID, !sessionID.isEmpty { args += ["--session", sessionID] }
        if skipPermissions { args.append("--dangerously-skip-permissions") }
        return args
    }

    /// Runtime permissions for OpenCode's headless process. Internal/read-only
    /// tools remain usable, while mutations follow Slate's selected mode. Rules
    /// later in each map are the more specific OpenCode matches.
    public static func permissionJSON(_ mode: PermissionMode, webSearch: Bool = false) -> String {
        var bash: [String: String] = ["*": "ask"]

        if mode == .autopilot {
            for pattern in [
                "pwd", "ls", "ls *", "rg *", "grep *", "git status", "git status *",
                "git diff", "git diff *", "git log", "git log *", "git show *",
                "git branch --show-current",
            ] {
                bash[pattern] = "allow"
            }
        }

        // Defense in depth: these stay denied even when OpenCode is launched
        // with --dangerously-skip-permissions from Slate's explicit global latch.
        for pattern in [
            "rm *", "rmdir *", "unlink *", "find * -delete*",
            "git clean *", "git reset --hard*", "git checkout -- *",
            "sudo *", "doas *", "launchctl *",
            "kill *", "pkill *", "killall *",
            "curl *", "wget *", "nc *", "netcat *", "ssh *", "scp *", "rsync *",
        ] {
            bash[pattern] = "deny"
        }

        let permissions: [String: Any] = [
            "*": "allow",
            "edit": mode == .ask ? "ask" : "allow",
            "bash": bash,
            "external_directory": "deny",
            "webfetch": webSearch ? "allow" : "deny",
            "websearch": webSearch ? "allow" : "deny",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: permissions,
                                                       options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"*":"ask"}"#
        }
        return json
    }

    public static func parse(_ line: String) -> [Event] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        var events: [Event] = []
        if let session = object["sessionID"] as? String, !session.isEmpty {
            events.append(.sessionStarted(session))
        }
        let part = object["part"] as? [String: Any]
        switch type {
        case "text":
            if let text = part?["text"] as? String, !text.isEmpty { events.append(.text(text)) }
        case "reasoning":
            if let text = part?["text"] as? String, !text.isEmpty { events.append(.reasoning(text)) }
        case "tool_use", "tool":
            let name = (part?["tool"] as? String) ?? (part?["name"] as? String) ?? "tool"
            let state = part?["state"] as? [String: Any]
            let title = (state?["title"] as? String) ?? ""
            events.append(.tool(title.isEmpty ? name : "\(name)  \(title)"))
        case "step_finish":
            let tokens = part?["tokens"] as? [String: Any]
            let total = tokens?["total"] as? Int
            let cost = (part?["cost"] as? NSNumber)?.doubleValue
            events.append(.finished(totalTokens: total, cost: cost))
        default:
            if events.isEmpty { events.append(.ignored) }
        }
        return events
    }

    public static func models(from output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { raw in
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.contains("/"), !id.contains(" "), seen.insert(id).inserted else { return nil }
            return id
        }
    }
}
