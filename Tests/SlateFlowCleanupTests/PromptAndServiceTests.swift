import Testing
@testable import SlateFlowCleanup

// MARK: Prompt structure

@Test func promptCarriesAntiAnsweringRule() {
    let p = CleanupPrompt.build(style: .light, appCategory: .other, dictionary: ["Lange & Co.", "Slate"])
    #expect(p.contains("NEVER answer"))
    #expect(p.contains("<transcript>"))
    #expect(p.contains("Lange & Co."))
    #expect(p.contains("Slate"))
    #expect(!p.lowercased().contains("translate the"))   // never instructs translation
}

@Test func promptAdaptsToneToCategory() {
    let mail = CleanupPrompt.build(style: .medium, appCategory: .email, dictionary: [])
    let chat = CleanupPrompt.build(style: .medium, appCategory: .messaging, dictionary: [])
    #expect(mail.contains("formal"))
    #expect(chat.contains("casual") || chat.contains("relaxed"))
}

// MARK: Service fallbacks

@Test func busyEngineFallsBackToRules() async {
    let svc = CleanupService(generate: { _, _ in "SHOULD NOT RUN" }, isBusy: { true })
    let out = await svc.polish("ja punkt", language: "de", style: .light,
                               appCategory: .other, dictionary: [])
    #expect(out == "ja.")                       // rules ran, LLM skipped
}

@Test func noneStyleSkipsLLM() async {
    let svc = CleanupService(generate: { _, _ in "SHOULD NOT RUN" }, isBusy: { false })
    let out = await svc.polish("hallo punkt", language: "de", style: .none,
                               appCategory: .other, dictionary: [])
    #expect(out == "hallo.")
}

@Test func timeoutFallsBackToRules() async {
    let svc = CleanupService(generate: { _, _ in
        try await Task.sleep(for: .seconds(10)); return "x"
    }, isBusy: { false }, timeout: 0.05)
    let out = await svc.polish("test eins", language: "de", style: .light,
                               appCategory: .other, dictionary: [])
    #expect(out == "test eins")
}

@Test func successReturnsCleaned() async {
    let svc = CleanupService(generate: { _, _ in "Hallo Welt." }, isBusy: { false })
    let out = await svc.polish("hallo ähm welt", language: "de", style: .light,
                               appCategory: .other, dictionary: [])
    #expect(out == "Hallo Welt.")
}

@Test func runawayOutputFallsBackToRules() async {
    let svc = CleanupService(generate: { _, _ in String(repeating: "blah ", count: 500) },
                             isBusy: { false })
    let out = await svc.polish("kurz", language: "de", style: .light,
                               appCategory: .other, dictionary: [])
    #expect(out == "kurz")                      // 4x-input guard rejected the runaway
}

@Test func emptyLLMOutputFallsBackToRules() async {
    let svc = CleanupService(generate: { _, _ in "  " }, isBusy: { false })
    let out = await svc.polish("etwas text", language: "de", style: .light,
                               appCategory: .other, dictionary: [])
    #expect(out == "etwas text")
}

@Test func messagingStripsTrailingPeriod() async {
    let svc = CleanupService(generate: { _, _ in "Bis gleich." }, isBusy: { false })
    let out = await svc.polish("bis gleich", language: "de", style: .light,
                               appCategory: .messaging, dictionary: [])
    #expect(out == "Bis gleich")
}
