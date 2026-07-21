import Foundation

/// One seat in an Agent Chat roundtable.
public struct RoundtableParticipant: Codable, Sendable, Equatable, Identifiable {
    public var id: String        // model ref: local path | "cloud:<id>" | "opencode:<id>" | "claude-code"
    public var name: String      // display name (prettified model name)
    public var persona: String   // "" = no persona, else a short role instruction
    public var index: Int        // 0-based seat, drives per-speaker color + labeling

    public init(id: String, name: String, persona: String = "", index: Int) {
        self.id = id; self.name = name; self.persona = persona; self.index = index
    }
}

/// Pure orchestration for the multi-model roundtable: system prompts, per-speaker
/// prompt assembly (role relabeling so each model sees the shared transcript
/// correctly), and turn order. No engines, no I/O — unit-testable.
public enum Roundtable {
    /// Agent Chat deliberately uses a bounded context per seat. Holding two or
    /// three 32K KV caches at once can consume more memory than the model files
    /// themselves and makes small-model roundtables unusable on a 24 GB Mac.
    public static let localContextWindow = 8_192
    public static let maxResponseTokens = 320   // keep turns short so a live roundtable is readable
    /// Hard generation CEILING per turn (not a target), sized to keep a live
    /// roundtable snappy. It gives a light reasoning model room to finish a short
    /// `<think>` block and still answer; `clampAnswer` trims the visible reply to a
    /// few sentences regardless. A seat that still returns nothing (a heavy reasoning
    /// model that never stops thinking) is retried once, then shown as a placeholder
    /// so alternation always holds - rather than blowing the budget (and latency) up
    /// for every turn.
    public static let maxTurnTokens = 1_100
    public static let estimatedKVBytesPerToken = 160_000.0

    /// Conservative preflight estimate shared by the setup UI and the runtime
    /// guard, so the number shown before Start cannot contradict the decision
    /// made after Start. `fileSizesGB` contains local seats only.
    public static func estimatedLocalMemoryGB(fileSizesGB: [Double],
                                              contextTokens: Int = localContextWindow) -> Double {
        let modelGB = fileSizesGB.filter { $0.isFinite && $0 > 0 }.reduce(0, +)
        let kvGBPerModel = Double(max(0, contextTokens)) * estimatedKVBytesPerToken / 1_073_741_824
        return modelGB + kvGBPerModel * Double(fileSizesGB.count)
    }

    /// Remove a leading name echo from a turn. Despite the prompt, models often
    /// prefix their reply with a label - "[Mistral 7B]: …", "Mistral 7B: …" or
    /// "**Mistral 7B**: …" - which reads terribly under the bubble's own name
    /// label. Strips any leading "[…]:" bracket label, and the speaker's OWN name
    /// with a following colon/comma/dash (other names are left alone - addressing
    /// another participant is legitimate content).
    public static func stripNameEcho(_ text: String, speaker: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "[Anything short]:" at the very start is always an echo label.
        if let r = t.range(of: #"^\[[^\]\n]{1,48}\]\s*:\s*"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        // The speaker's own name (optionally bold) followed by ':' / ',' / '-'.
        let escaped = NSRegularExpression.escapedPattern(for: speaker)
        if let r = t.range(of: "^(\\*\\*)?\(escaped)(\\*\\*)?\\s*[:,-]\\s+",
                           options: [.regularExpression, .caseInsensitive]) {
            t.removeSubrange(r)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clamp a committed turn to a few sentences so a verbose (often reasoning)
    /// model can't dominate a live roundtable with a wall of text. The prompt asks
    /// for 2-3 sentences; this GUARANTEES it regardless of whether the model obeys.
    /// Keeps whole sentences; falls back to a hard character cap for run-ons.
    public static func clampAnswer(_ text: String, maxSentences: Int = 4, maxCharacters: Int = 700) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        var sentences: [String] = []
        var current = ""
        for ch in trimmed {
            current.append(ch)
            if ".!?…".contains(ch) {
                sentences.append(current); current = ""
                if sentences.count >= maxSentences { break }
            }
        }
        if sentences.count < maxSentences,
           !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current)
        }
        var result = sentences.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { result = trimmed }
        if result.count > maxCharacters {
            result = String(result.prefix(maxCharacters)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return result
    }

    /// Turn order for a round. Normal rounds: the whole roster in seat order.
    /// The synthesis round: a single speaker (seat 0) who summarizes the discussion.
    public static func speakerOrder(roster: [RoundtableParticipant], synthesis: Bool) -> [RoundtableParticipant] {
        if synthesis { return roster.first.map { [$0] } ?? [] }
        return roster
    }

    /// The prior speaker turns for the CURRENT topic only: everything after the
    /// last user (topic) message, kept to speaker-attributed assistant turns.
    /// Scoping to the last topic stops a second discussion in the same
    /// conversation from replaying the previous one; requiring a `.speaker`
    /// excludes un-attributed notices (e.g. a failed seat's error placeholder).
    public static func currentDiscussion(in messages: [ChatMessage]) -> [ChatMessage] {
        let start = (messages.lastIndex(where: { $0.role == .user }).map { $0 + 1 }) ?? 0
        return Array(messages[start...]).filter { $0.role == .assistant && $0.speaker != nil }
    }

    /// The system prompt for one participant: who they are, the roster, the topic,
    /// the round context, and the discussion rules.
    public static func systemPrompt(for me: RoundtableParticipant, roster: [RoundtableParticipant],
                                    topic: String, round: Int, totalRounds: Int, isSynthesis: Bool) -> String {
        let others = roster.filter { $0.index != me.index }.map(\.name)
        let othersLine = others.isEmpty ? "You are the only participant." :
            "The other participants are: \(others.joined(separator: ", "))."
        var lines = [
            "You are \"\(me.name)\", one of \(roster.count) AI models in a live roundtable discussion.",
            othersLine,
        ]
        if !me.persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Your role in this discussion: \(me.persona).")
        }
        if isSynthesis {
            lines.append("This is the FINAL synthesis of the whole discussion. In one short paragraph, capture the key points raised, note where the group agreed or disagreed, and give the group's single best combined answer. Do not speak as one participant - summarize the group.")
        } else {
            lines.append("This is round \(round + 1) of \(totalRounds). Build on the good points, challenge weak ones by name, add a genuinely new angle, and do not just repeat what has already been said.")
        }
        // Direct-answer + brevity. The no-reasoning rule matters most for reasoning
        // models: without it they spend the whole turn "thinking" and emit no
        // visible answer, so their turn is dropped and the roundtable looks broken.
        lines.append("Answer directly and immediately. Do NOT think out loud, narrate your reasoning, or use <think> tags - give only your final answer.")
        lines.append("Be brief: 2-3 sentences, one short paragraph. Make your single best point and stop; do not ramble, list, or repeat. Speak in first person as \(me.name); never refer to yourself in the third person, and do NOT prefix your reply with your own name or a label.")
        lines.append("")
        lines.append("Topic under discussion:")
        lines.append(topic)
        // Qwen3-family soft switch to disable chain-of-thought. Reasoning seats (e.g.
        return lines.joined(separator: "\n")
    }

    /// The prompt messages fed to `me`'s engine. Starts with the system prompt and
    /// the topic (as a user turn), then replays the shared discussion with roles
    /// relabeled from `me`'s point of view: me's own turns are `.assistant`; every
    /// other speaker's turn is `.user` prefixed with "[Name]: ". Always ends on a
    /// `.user` turn so the model produces the next contribution.
    ///
    /// `discussion` is the prior speaker turns only (role `.assistant`, each tagged
    /// with `.speaker`); the seed topic is passed separately via `topic`.
    public static func prompt(for me: RoundtableParticipant, roster: [RoundtableParticipant],
                              topic: String, discussion: [ChatMessage],
                              round: Int, totalRounds: Int, isSynthesis: Bool) -> [ChatMessage] {
        var msgs: [ChatMessage] = [
            ChatMessage(role: .system,
                        content: systemPrompt(for: me, roster: roster, topic: topic,
                                              round: round, totalRounds: totalRounds, isSynthesis: isSynthesis)),
            ChatMessage(role: .user, content: "The topic for discussion is:\n\(topic)"),
        ]
        for turn in discussion where turn.role == .assistant {
            if turn.speaker == me.name {
                msgs.append(ChatMessage(role: .assistant, content: turn.content))
            } else {
                let who = turn.speaker ?? "Another participant"
                msgs.append(ChatMessage(role: .user, content: "[\(who)]: \(turn.content)"))
            }
        }
        if msgs.last?.role != .user {
            msgs.append(ChatMessage(role: .user,
                                    content: isSynthesis ? "Now give your synthesis." : "Add your perspective."))
        }
        return msgs
    }
}
