import Foundation

/// How aggressively the LLM polishes a transcript (spec item 6). `.none` skips
/// the LLM entirely (raw mode); rule-based passes still run.
public enum CleanupStyle: String, Sendable, CaseIterable {
    case none, light, medium, high
}

/// Frontmost-app category - drives tone + trailing-period policy (spec items 7/8).
public enum AppCategory: String, Sendable {
    case messaging, email, code, other
}
