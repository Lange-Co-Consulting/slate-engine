import Foundation

public enum CommandBlocklist {
    // Conservative, case-insensitive patterns. These rules apply in every
    // permission mode, including Skip permissions. Over-denial is acceptable:
    // the file tools provide a reviewable alternative for project changes.
    private static let patterns: [(label: String, regex: String)] = [
        ("file deletion",          #"\b(rm|rmdir|unlink|shred|srm|truncate)\b|\bfind\b[^\n]*\s-delete\b"#),
        ("destructive git",        #"\bgit\s+(clean\b|reset\s+--hard\b|checkout\s+--\s|restore\b)"#),
        ("file move",              #"(^|[;&|]\s*)mv\s"#),
        ("privilege escalation",   #"\bsudo\b"#),
        ("force push",             #"\bgit\s+push\b[^\n]*(--force|-f\b)"#),
        ("disk write",             #"\bdd\b\s+if="#),
        ("filesystem format",      #"\bmkfs\b|\bdiskutil\s+erase"#),
        ("pipe-to-shell",          #"\|\s*(sh|bash|zsh)\b"#),
        ("secret path access",     #"(~|/)(\.ssh|\.aws|\.gnupg|library/keychains)(/|\b)|\$(home|ssh_auth_sock)\b"#),
        ("network transfer",       #"\b(curl|wget|nc|ncat|netcat|scp|sftp|ssh|ftp)\b"#),
        ("fork bomb",              #":\(\)\s*\{"#),
        ("recursive chmod/chown",  #"\b(chmod|chown)\s+-[a-z]*R"#),
        ("process termination",    #"\b(kill|killall|pkill)\b"#),
        ("shutdown/reboot",        #"\b(shutdown|reboot|halt|launchctl)\b"#),
        ("macOS data deletion",    #"\b(defaults|security)\s+delete\b"#),
    ]

    /// Returns a human-readable reason if the command is blocked, else nil.
    public static func match(_ command: String) -> String? {
        let lower = command.lowercased()
        for p in patterns where lower.range(of: p.regex, options: .regularExpression) != nil {
            return "Blocked (\(p.label)): refusing to run \"\(command)\""
        }
        return nil
    }

    /// Shell syntax is too expressive to prove that a command is read-only and
    /// workspace-confined. Auto therefore permits only commands that cannot
    /// name a path; all useful shell work reaches the approval UI.
    public static func risk(_ command: String) -> ActionRisk {
        if match(command) != nil { return .destructive }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return .safe }
        if trimmed.range(of: #"(^|\s)(>|>>|2>|&>)"#, options: .regularExpression) != nil {
            return .sensitive
        }
        let safePatterns = [
            #"^pwd\s*$"#,
            #"^ls(\s+-[a-z0-9@]+)*\s*$"#,
        ]
        return safePatterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
            ? .safe : .sensitive
    }
}
