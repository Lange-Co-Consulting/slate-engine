import Testing
import Foundation
@testable import SlateLlama
import SlateCore

/// Runs a REAL two-model roundtable through the actual Roundtable prompt helpers +
/// live llama engines and asserts the behaviours the operator asked for: strict
/// speaker alternation (no model answering twice in a row), non-empty turns, a
/// final synthesis, and brief answers.
///
/// Gated (heavy: loads two models). Run with two small local models, e.g.:
///   SLATE_RT_SMOKE=1 \
///   SLATE_RT_MODEL_A=~/Models/gemma-2-2b-it-Q4_K_M.gguf \
///   SLATE_RT_MODEL_B=~/Models/Qwen2.5-3B-Instruct-Q4_K_M.gguf \
///   swift test --filter RoundtableSmokeTests
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLATE_RT_SMOKE"] == "1"))
func roundtableAlternatesStaysBriefAndSynthesizes() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let a = env["SLATE_RT_MODEL_A"], let b = env["SLATE_RT_MODEL_B"] else { return }
    let ngl = env["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 999
    let engines: [String: LlamaEngine] = [
        "a": try LlamaEngine(modelPath: (a as NSString).expandingTildeInPath, nCtx: 4096, nGpuLayers: ngl),
        "b": try LlamaEngine(modelPath: (b as NSString).expandingTildeInPath, nCtx: 4096, nGpuLayers: ngl),
    ]
    let roster = [
        RoundtableParticipant(id: "0:a", modelRef: "a", name: "Alpha", index: 0),
        RoundtableParticipant(id: "1:b", modelRef: "b", name: "Beta", index: 1),
    ]
    let topic = "Is a hot dog a sandwich? Give a clear position."
    let rounds = 2
    var transcript: [(speaker: String, text: String)] = []

    func runTurn(_ me: RoundtableParticipant, round: Int, isSynthesis: Bool) async throws {
        let discussion = transcript.map { ChatMessage(role: .assistant, content: $0.text, speaker: $0.speaker) }
        let msgs = Roundtable.prompt(for: me, roster: roster, topic: topic, discussion: discussion,
                                     round: round, totalRounds: rounds, isSynthesis: isSynthesis)
        var out = ""
        for try await piece in await engines[me.modelRef]!.generate(
            messages: msgs, grammar: nil,
            options: GenOptions(temperature: 0.7, maxTokens: Roundtable.maxTurnTokens)) {
            out += piece
        }
        let clean = Roundtable.clampAnswer(Reasoning.strip(out).trimmingCharacters(in: .whitespacesAndNewlines))
        transcript.append((isSynthesis ? "Synthesis" : me.name, clean))
    }

    for round in 0..<rounds {
        for speaker in Roundtable.speakerOrder(roster: roster, synthesis: false) {
            try await runTurn(speaker, round: round, isSynthesis: false)
        }
    }
    if let host = Roundtable.speakerOrder(roster: roster, synthesis: true).first {
        try await runTurn(host, round: rounds, isSynthesis: true)
    }

    for (s, t) in transcript {
        print("RT_TURN [\(s)] (\(t.split(separator: " ").count) words): \(t.prefix(180))")
    }

    // 2 rounds × 2 speakers + 1 synthesis = 5 turns.
    #expect(transcript.count == 5)
    // Strict alternation across the discussion turns (no model twice in a row).
    #expect(transcript[0].speaker == "Alpha")
    #expect(transcript[1].speaker == "Beta")
    #expect(transcript[2].speaker == "Alpha")
    #expect(transcript[3].speaker == "Beta")
    for i in 1..<4 { #expect(transcript[i].speaker != transcript[i - 1].speaker) }
    // The last turn is a distinct synthesis.
    #expect(transcript[4].speaker == "Synthesis")
    // No vanished turns.
    for t in transcript { #expect(!t.text.isEmpty) }
    // Focused: each discussion turn is short enough to follow live.
    for t in transcript.prefix(4) { #expect(t.text.split(separator: " ").count <= 140) }
}

/// The exact failure the operator hit: Ornith (a REASONING model) spent its whole
/// turn "thinking" and produced no visible answer, so its turn was skipped and the
/// other model appeared to answer 3× in a row. This proves the fix on that very
/// model: with the no-thinking prompt + generous budget (+ the app's one retry),
/// Ornith yields a real, non-empty, brief answer — so it can never vanish.
///
///   SLATE_RT_ORNITH=1 SLATE_RT_MODEL=~/Models/ornith-1.0-9b-Q8_0.gguf \
///   SLATE_TEST_NGL=999 swift test --filter reasoningSeatProducesVisibleAnswer
@Test(.enabled(if: ProcessInfo.processInfo.environment["SLATE_RT_ORNITH"] == "1"))
func reasoningSeatProducesVisibleAnswer() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["SLATE_RT_MODEL"] else { return }
    let ngl = env["SLATE_TEST_NGL"].flatMap { Int32($0) } ?? 999
    let engine = try LlamaEngine(modelPath: (path as NSString).expandingTildeInPath, nCtx: 4096, nGpuLayers: ngl)
    let roster = [
        RoundtableParticipant(id: "0:a", modelRef: "a", name: "Ornith", index: 0),
        RoundtableParticipant(id: "1:b", modelRef: "b", name: "Mistral", index: 1),
    ]
    let me = roster[0]
    let topic = "Is the BMW M6 F06 or the S500 Coupe 2018 the better sports car?"

    func attempt(_ extra: [ChatMessage]) async throws -> String {
        let msgs = Roundtable.prompt(for: me, roster: roster, topic: topic, discussion: [],
                                     round: 0, totalRounds: 3, isSynthesis: false) + extra
        var out = ""
        for try await piece in await engine.generate(
            messages: msgs, grammar: nil,
            options: GenOptions(temperature: 0.7, maxTokens: Roundtable.maxTurnTokens)) {
            out += piece
        }
        print("ORNITH_RAW (\(out.count) chars): \(out.prefix(200)) … \(out.suffix(120))")
        return Roundtable.clampAnswer(Reasoning.strip(out).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var answer = try await attempt([])
    if answer.isEmpty {   // the app's one retry with a hard no-thinking nudge
        answer = try await attempt([ChatMessage(role: .user,
            content: "You have not answered yet. Reply now with ONLY your final answer in 2-3 sentences. Do not think out loud or use <think> tags.")])
    }
    print("ORNITH_TURN (\(answer.split(separator: " ").count) words): \(answer.prefix(300))")
    #expect(!answer.isEmpty)                         // it no longer vanishes
    #expect(answer.split(separator: " ").count <= 160)   // and stays brief
}
