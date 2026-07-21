import Foundation

public enum PermissionMode: String, Sendable, CaseIterable {
    case autopilot, acceptEdits, ask

    /// New and malformed sessions fail closed. Autopilot remains an explicit
    /// opt-in because shell commands are full local processes, not a sandbox.
    public static let recommendedDefault: PermissionMode = .ask
}

public enum ActionKind: Sendable, Equatable, Hashable { case fileWrite, shellCommand, localTool }

/// A coarse risk signal produced by Slate itself. It is deliberately based on
/// the requested action, not on the model's claim that an action is safe.
public enum ActionRisk: Sendable, Equatable, Hashable {
    case safe, sensitive, destructive
}

public enum PermissionPolicy {
    /// `skipPermissions` is intentionally only effective in Autopilot. Merely
    /// selecting Auto must never become the equivalent of Claude Code's
    /// `--dangerously-skip-permissions` flag.
    public static func requiresConfirmation(mode: PermissionMode,
                                            kind: ActionKind,
                                            risk: ActionRisk = .sensitive,
                                            skipPermissions: Bool = false) -> Bool {
        switch mode {
        case .ask:
            return true
        case .acceptEdits:
            return kind == .shellCommand || kind == .localTool || risk == .destructive
        case .autopilot:
            return skipPermissions ? false : risk != .safe
        }
    }
}

public enum FileChangeRisk {
    /// Small edits and ordinary new files are suitable for Auto. Whole-file
    /// replacement, security/configuration files and deletion-heavy changes
    /// remain reviewable unless the user explicitly enabled Skip permissions.
    public static func classify(path: String, old: String?, new: String,
                                wholeFileReplacement: Bool = false) -> ActionRisk {
        let lower = path.lowercased()
        let sensitiveNames = [
            ".env", ".git/", ".ssh/", "credentials", "secrets", "keychain",
            "entitlements", "info.plist", "package.swift", "package.resolved",
            "project.pbxproj", "slate.md", "agents.md"
        ]
        if sensitiveNames.contains(where: { lower == $0 || lower.contains($0) }) {
            return .sensitive
        }
        guard let old else { return .safe }
        if old == new { return .safe }
        if !old.isEmpty && new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .destructive
        }
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).count
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).count
        let removed = max(0, oldLines - newLines)
        if removed >= max(20, oldLines / 2) { return .destructive }
        if wholeFileReplacement { return .sensitive }
        return .safe
    }
}

public struct ApprovalRequest: Sendable, Equatable {
    public let kind: ActionKind
    public let risk: ActionRisk
    public let title: String
    public let detail: String   // diff preview or the command
    /// Stable path/command used to scope "allow for this session" narrowly.
    public let scope: String
    public init(kind: ActionKind, risk: ActionRisk = .sensitive,
                title: String, detail: String, scope: String? = nil) {
        self.kind = kind; self.risk = risk; self.title = title
        self.detail = detail; self.scope = scope ?? detail
    }
}

/// The UI implements this. The default/test gate auto-approves.
public protocol ApprovalGate: Sendable {
    func confirm(_ request: ApprovalRequest) async -> Bool
}

public struct AutoApproveGate: ApprovalGate {
    public init() {}
    public func confirm(_ request: ApprovalRequest) async -> Bool { true }
}
