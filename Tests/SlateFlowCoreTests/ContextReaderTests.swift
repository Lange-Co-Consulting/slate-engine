import Testing
@testable import SlateFlowCore

@Test func categorizesKnownBundleIDs() {
    #expect(ContextReader.category(forBundleID: "com.apple.mail") == "email")
    #expect(ContextReader.category(forBundleID: "com.microsoft.Outlook") == "email")
    #expect(ContextReader.category(forBundleID: "com.tinyspeck.slackmacgap") == "messaging")
    #expect(ContextReader.category(forBundleID: "net.whatsapp.WhatsApp") == "messaging")
    #expect(ContextReader.category(forBundleID: "com.apple.MobileSMS") == "messaging")
    #expect(ContextReader.category(forBundleID: "ru.keepcoder.Telegram") == "messaging")
    #expect(ContextReader.category(forBundleID: "com.apple.Terminal") == "code")
    #expect(ContextReader.category(forBundleID: "com.googlecode.iterm2") == "code")
    #expect(ContextReader.category(forBundleID: "com.microsoft.VSCode") == "code")
    #expect(ContextReader.category(forBundleID: "com.apple.dt.Xcode") == "code")
}

@Test func unknownBundleIsOther() {
    #expect(ContextReader.category(forBundleID: "com.random.unknown.app") == "other")
    #expect(ContextReader.category(forBundleID: nil) == "other")
}

@Test func slateItselfIsOther() {
    // Dictating into Slate's own chat composer: neutral tone, keep periods.
    #expect(ContextReader.category(forBundleID: "com.langeundco.slate") == "other")
}
