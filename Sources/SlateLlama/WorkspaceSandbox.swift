import Foundation
import SlateCore

/// A least-privilege Seatbelt profile for code-agent shell commands. The
/// workspace and an ephemeral scratch directory are the only writable areas;
/// the user's home, Keychain, network and inherited environment stay out of
/// reach even after the user approved a command.
enum WorkspaceSandbox {
    /// NSURL intentionally preserves macOS's `/var` compatibility alias.
    /// Seatbelt evaluates the physical `/private/var` path, so normalize the
    /// few OS-owned aliases without accepting arbitrary user symlinks.
    static func physicalURL(_ url: URL) -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolved.path
        let aliases = ["/var": "/private/var", "/tmp": "/private/tmp", "/etc": "/private/etc"]
        for (logical, physical) in aliases where path == logical || path.hasPrefix(logical + "/") {
            return URL(fileURLWithPath: physical + path.dropFirst(logical.count), isDirectory: resolved.hasDirectoryPath)
        }
        return resolved
    }

    static func profile(workspace: URL, scratch: URL) -> String {
        let workspacePath = physicalURL(workspace).path
        let scratchPath = physicalURL(scratch).path
        func literal(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let systemRead = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/dev/null", "/dev/urandom"]
            .map { "(subpath \(literal($0)))" }.joined(separator: "\n  ")
        return """
        (version 1)
        ;; Required baseline for platform binaries: dyld, safe inherited file
        ;; descriptors and a small set of macOS runtime lookups. The explicit
        ;; deny below still wins over its narrowly-scoped syslog exception.
        (import "system.sb")
        (deny default)
        (allow process-exec)
        (allow process-fork)
        (allow signal (target self))
        (allow process-info-pidinfo (target self))
        (allow sysctl-read)
        (allow file-read*
          \(systemRead)
          (subpath \(literal(workspacePath)))
          (subpath \(literal(scratchPath))))
        ;; `pwd` and relative paths require metadata access to the parent
        ;; components, but not read access to their contents.
        (allow file-read-metadata file-test-existence
          (path-ancestors \(literal(workspacePath)))
          (path-ancestors \(literal(scratchPath))))
        (allow file-write*
          (subpath \(literal(workspacePath)))
          (subpath \(literal(scratchPath))))
        (deny network*)
        """
    }

    static func scratchDirectory() throws -> URL {
        let root = URL.applicationSupportDirectory
            .appendingPathComponent("Slate/ShellScratch", isDirectory: true)
        try PrivateStorage.ensureDirectory(root)
        let scratch = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateStorage.ensureDirectory(scratch)
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("home", isDirectory: true))
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("tmp", isDirectory: true))
        return scratch
    }

    static func environment(scratch: URL) -> [String: String] {
        let home = scratch.appendingPathComponent("home", isDirectory: true).path
        let tmp = scratch.appendingPathComponent("tmp", isDirectory: true).path
        return [
            "HOME": home,
            "TMPDIR": tmp,
            "XDG_CACHE_HOME": scratch.appendingPathComponent("cache", isDirectory: true).path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
        ]
    }
}
