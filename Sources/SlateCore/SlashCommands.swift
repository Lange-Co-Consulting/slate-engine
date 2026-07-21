import Foundation

/// A reusable prompt triggered by `/name`. Trailing text after the command name
/// replaces `{input}` in the template (or is appended if there's no placeholder).
public struct SlashCommand: Identifiable, Sendable, Equatable {
    public let name: String
    public let title: String
    public let summary: String
    public let template: String
    public var id: String { name }

    public init(name: String, title: String, summary: String, template: String) {
        self.name = name; self.title = title; self.summary = summary; self.template = template
    }

    public func expand(with input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.contains("{input}") {
            return template.replacingOccurrences(of: "{input}", with: trimmed)
        }
        return trimmed.isEmpty ? template : template + "\n\n" + trimmed
    }
}

public enum SlashCommands {
    public static let builtins: [SlashCommand] = [
        .init(name: "explain", title: "Explain", summary: "Explain code or a concept",
              template: "Explain the following clearly and concisely:\n{input}"),
        .init(name: "fix", title: "Fix", summary: "Find and fix the bug",
              template: "Find and fix the bug. Make the change in the files, then summarize what was wrong.\n{input}"),
        .init(name: "test", title: "Tests", summary: "Write tests",
              template: "Write thorough tests for the following, create the test file(s), and run them:\n{input}"),
        .init(name: "review", title: "Review", summary: "Review the recent changes",
              template: "Review the current changes for correctness, edge cases, and clarity. List concrete issues."),
        .init(name: "refactor", title: "Refactor", summary: "Refactor for clarity",
              template: "Refactor the following for clarity and simplicity without changing behavior; apply the edits:\n{input}"),
        .init(name: "commit", title: "Commit msg", summary: "Draft a commit message",
              template: "Write a concise, conventional-commit message for the current changes (run git diff if needed)."),

        // Claude Code-style workflow commands. Pure structured prompts, so they
        // work with any model, local or cloud. Numbered steps on purpose: small
        // local models follow an explicit sequence far more reliably than prose.
        .init(name: "research", title: "Research", summary: "Decision-ready briefing on a topic",
              template: """
              Research the topic below and give me a decision-ready briefing.
              1. Restate the question and what a good answer must cover.
              2. Break it into the key sub-questions.
              3. Answer each with concrete facts; where you are unsure, say so plainly.
              4. Note the trade-offs and any conflicting views.
              5. End with a short "Bottom line" and, if useful, a recommendation.
              Topic: {input}
              """),
        .init(name: "brainstorm", title: "Brainstorm", summary: "Explore an idea before building",
              template: """
              Brainstorm this with me BEFORE writing any code — do not implement yet.
              1. Restate the goal and who it is for.
              2. Surface the key open questions and my likely constraints.
              3. Propose 2-3 distinct approaches with concrete trade-offs, and recommend one.
              4. Sketch the design of the recommended approach (parts, data flow, edge cases).
              Keep it tight, then ask me to confirm before building.
              Idea: {input}
              """),
        .init(name: "plan", title: "Plan", summary: "Step-by-step implementation plan",
              template: """
              Write a concrete implementation plan for the task below — detailed enough
              that someone with no context could execute it. Do not implement yet.
              For each step give: the exact files to touch, what to change, and how to
              verify it. Prefer small, testable increments and say where tests go.
              Task: {input}
              """),
        .init(name: "goal", title: "Goal (autonomous)", summary: "Work autonomously until a goal is met",
              template: """
              Work autonomously toward this goal until it is actually met — not just attempted.
              1. State the goal as a checkable condition ("done when …").
              2. Make a short plan.
              3. Execute it with the available tools — edit files and run commands as needed.
              4. After each step, check your work against the done-condition.
              5. Continue until that condition is verifiably true, then stop and report exactly
                 what you changed and how you verified it.
              If you get stuck, say what is blocking you instead of guessing.
              Goal: {input}
              """),
        .init(name: "debug", title: "Debug", summary: "Systematic root-cause debugging",
              template: """
              Debug this systematically — do not guess-and-check.
              1. Restate the symptom and how to reproduce it.
              2. Form 1-3 concrete hypotheses about the cause.
              3. Gather evidence for/against each (read the code, add a check, run it).
              4. Identify the root cause, with evidence.
              5. Apply the minimal fix and verify the symptom is gone.
              Report the root cause and the fix.
              Problem: {input}
              """),
        .init(name: "spec", title: "Spec", summary: "Write a design/spec document",
              template: """
              Write a clear specification for the following. Cover: goal and non-goals,
              user-facing behavior, the components and how they interact, data/state,
              error handling, and how it will be tested. Flag open questions instead of
              hand-waving. Output as structured markdown.
              Feature: {input}
              """),
        .init(name: "optimize", title: "Optimize", summary: "Improve perf/clarity, same behavior",
              template: """
              Optimize the following for performance and clarity WITHOUT changing behavior.
              1. Identify the concrete bottlenecks or rough spots, and say why.
              2. Propose the changes with their expected impact.
              3. Apply the safe ones and explain each.
              4. Note anything risky you did NOT change, and why.
              Call out any behavior you might affect.
              Target: {input}
              """),
        .init(name: "document", title: "Document", summary: "Write docs matching the codebase",
              template: """
              Write clear documentation for the following: what it does, how to use it
              (with a minimal example), its inputs/outputs, and any gotchas. Match the
              style and depth of the surrounding code's existing docs. For a whole module,
              start with a one-paragraph overview.
              Subject: {input}
              """),
        .init(name: "compact", title: "Compact", summary: "Summarize older messages to free up context",
              template: "Summarize our conversation so far into a compact briefing and continue from it."),
    ]

    /// Claude Code's OWN slash commands, run by the CLI when Cloud is active. Slate
    /// only lists them for discoverability - they pass through verbatim (never
    /// expanded), so their template is unused.
    public static let claudeBuiltins: [SlashCommand] = [
        .init(name: "compact", title: "Compact", summary: "Summarize & shrink the context", template: ""),
        .init(name: "clear", title: "Clear", summary: "Clear the conversation history", template: ""),
        .init(name: "cost", title: "Cost", summary: "Show token usage & cost for this session", template: ""),
        .init(name: "context", title: "Context", summary: "Visualize context-window usage", template: ""),
        .init(name: "model", title: "Model", summary: "Switch the Claude model", template: ""),
        .init(name: "review", title: "Review", summary: "Review a pull request", template: ""),
        .init(name: "pr-comments", title: "PR comments", summary: "Fetch pull-request comments", template: ""),
        .init(name: "init", title: "Init", summary: "Create or update CLAUDE.md for this repo", template: ""),
        .init(name: "memory", title: "Memory", summary: "Edit Claude memory files", template: ""),
        .init(name: "agents", title: "Agents", summary: "Manage subagents", template: ""),
        .init(name: "mcp", title: "MCP", summary: "Manage MCP servers", template: ""),
        .init(name: "resume", title: "Resume", summary: "Resume a past session", template: ""),
        .init(name: "status", title: "Status", summary: "Show session & account status", template: ""),
        .init(name: "config", title: "Config", summary: "Open configuration", template: ""),
        .init(name: "export", title: "Export", summary: "Export this conversation", template: ""),
        .init(name: "release-notes", title: "Release notes", summary: "Show what's new", template: ""),
        .init(name: "help", title: "Help", summary: "List all available commands", template: ""),
    ]

    /// Commands whose name starts with `prefix` (the text after `/`, no slash).
    public static func matches(_ prefix: String, custom: [SlashCommand] = []) -> [SlashCommand] {
        filter(builtins + custom, prefix: prefix)
    }

    /// Prefix-filter an arbitrary command pool (used for the Cloud command list).
    public static func filter(_ pool: [SlashCommand], prefix: String) -> [SlashCommand] {
        let p = prefix.lowercased()
        return p.isEmpty ? pool : pool.filter { $0.name.hasPrefix(p) }
    }

    /// If `text` is `/name rest…`, expand it; otherwise return text unchanged.
    public static func expand(_ text: String, custom: [SlashCommand] = []) -> String {
        guard text.hasPrefix("/") else { return text }
        let body = String(text.dropFirst())
        let name = String(body.prefix { !$0.isWhitespace })
        let rest = String(body.dropFirst(name.count))
        guard let cmd = (builtins + custom).first(where: { $0.name == name.lowercased() }) else { return text }
        return cmd.expand(with: rest)
    }
}
