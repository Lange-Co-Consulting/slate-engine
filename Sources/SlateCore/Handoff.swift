import Foundation

/// Export a Slate session as a markdown brief to paste back into Claude Code when the
/// limit resets - closing the round-trip (CC → Slate → CC).
public enum Handoff {
    public static func markdown(title: String, folder: String?, messages: [ChatMessage], changedFiles: [String]) -> String {
        var s = "# Slate handoff - \(title)\n\n"
        if let folder { s += "**Project:** `\(folder)`\n\n" }
        if !changedFiles.isEmpty {
            s += "## Files changed locally\n"
            s += changedFiles.map { "- `\($0)`" }.joined(separator: "\n") + "\n\n"
        }
        s += "## Conversation so far\n"
        for m in messages where m.role == .user || m.role == .assistant {
            let who = m.role == .user ? "User" : "Slate"
            let text = Reasoning.strip(m.content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { s += "\n**\(who):** \(text)\n" }
        }
        s += "\n---\nPlease continue from here.\n"
        return s
    }
}
