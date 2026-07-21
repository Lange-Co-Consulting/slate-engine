import Foundation

/// The transcript-polish pipeline: deterministic rules first, then (unless raw
/// mode / busy / slow) one LLM pass, then the trailing-period policy. Dictation
/// must NEVER block on a wedged model - every failure path returns the
/// rules-only text (spec §5).
public struct CleanupService: Sendable {
    /// (systemPrompt, userMessage) → model output. Wired to LlamaEngine by the app.
    public typealias Generate = @Sendable (String, String) async throws -> String

    let generate: Generate
    let isBusy: @Sendable () -> Bool
    let timeout: Double

    public init(generate: @escaping Generate,
                isBusy: @escaping @Sendable () -> Bool,
                timeout: Double = 3.0) {
        self.generate = generate
        self.isBusy = isBusy
        self.timeout = timeout
    }

    public func polish(_ raw: String, language: String?, style: CleanupStyle,
                       appCategory: AppCategory, dictionary: [String]) async -> String {
        // 1) Deterministic rules - always run, never depend on the model.
        let ruled = SpokenPunctuation.apply(raw, language: language)
        var text = ruled

        // 2) LLM pass - skipped in raw mode or when the engine is mid-generation.
        if style != .none, !isBusy() {
            let system = CleanupPrompt.build(style: style, appCategory: appCategory,
                                             dictionary: dictionary)
            let user = "<transcript>\(ruled)</transcript>"
            if let out = await raceWithTimeout(system: system, user: user) {
                let cleaned = out
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
                // Reject empties and runaways (a 4x blowup means the model
                // answered/rambled instead of transcribing).
                if !cleaned.isEmpty, cleaned.count <= max(80, ruled.count * 4) {
                    text = cleaned
                }
            }
        }

        // 3) Trailing-period policy (spec item 7).
        return TrailingPeriodPolicy.strip(text, appCategory: appCategory,
                                          sentences: TrailingPeriodPolicy.sentenceCount(text))
    }

    private func raceWithTimeout(system: String, user: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await generate(system, user) }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
