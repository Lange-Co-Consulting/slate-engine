import AppKit

/// Frontmost-app awareness (spec item 8): the bundle ID of the app being
/// dictated into decides tone (email = formal, chat = casual) and the
/// trailing-period policy. Pure category map is unit-tested; the frontmost
/// lookup is a one-liner over NSWorkspace. Categories are returned as raw
/// strings so SlateFlowCore stays independent of SlateFlowCleanup's enums.
public enum ContextReader {
    private static let email: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac",
        "com.airmailapp.airmail", "com.superhuman.electron", "com.mimestream.Mimestream",
    ]
    private static let messaging: Set<String> = [
        "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "com.apple.MobileSMS",
        "ru.keepcoder.Telegram", "com.hnc.Discord", "org.whispersystems.signal-desktop",
        "com.microsoft.teams2", "com.facebook.archon",
    ]
    private static let code: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.jetbrains.intellij",
        "com.todesktop.230313mzl4w4u92", "com.github.GitHubClient", "dev.zed.Zed",
    ]

    public static func category(forBundleID id: String?) -> String {
        guard let id else { return "other" }
        if email.contains(id) { return "email" }
        if messaging.contains(id) { return "messaging" }
        if code.contains(id) { return "code" }
        return "other"
    }

    /// Bundle ID of the app that will receive the dictation.
    @MainActor public static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
