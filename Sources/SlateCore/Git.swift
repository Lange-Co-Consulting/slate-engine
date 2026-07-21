import Foundation

/// Minimal git wrapper (via `/usr/bin/git`) so the agent's work can be reviewed and
/// committed without leaving Slate. Fails gracefully (empty results) if git or the
/// repo is unavailable.
public enum Git {
    private static let maxOutputBytes = 4 * 1_024 * 1_024
    private static let timeout: TimeInterval = 15
    public struct Change: Equatable, Sendable, Identifiable {
        public let status: String   // 2-char porcelain code, e.g. " M", "??", "A "
        public let path: String
        public var id: String { path }
        public var kind: String {
            let t = status.trimmingCharacters(in: .whitespaces)
            if status.contains("?") { return "new" }
            if t.contains("D") { return "deleted" }
            if t.contains("A") { return "added" }
            if t.contains("R") { return "renamed" }
            return "modified"
        }
    }

    @discardableResult
    static func run(_ args: [String], in folder: URL) -> (out: String, code: Int32) {
        let workspace = folder.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
              let scratch = try? scratchDirectory() else { return ("", -1) }
        defer { try? FileManager.default.removeItem(at: scratch) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        // Local repository config can name hooks, fsmonitor helpers, clean
        // filters and external diff tools. Keep Git itself in a sandbox and
        // allow it to exec only the known system Git binary; an untrusted repo
        // therefore cannot turn an innocent status/diff view into arbitrary
        // code running with access to the user's home or network.
        p.arguments = ["-p", sandboxProfile(workspace: workspace, scratch: scratch), "/usr/bin/git",
                       "-c", "core.hooksPath=/dev/null",
                       "-c", "core.fsmonitor=false",
                       "-c", "commit.gpgSign=false",
                       "-C", workspace.path] + args
        p.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": scratch.appendingPathComponent("home", isDirectory: true).path,
            "TMPDIR": scratch.appendingPathComponent("tmp", isDirectory: true).path,
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return ("", -1) }
        let timeoutWork = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        var data = Data()
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            data.append(chunk)
            if data.count > maxOutputBytes {
                if p.isRunning { p.terminate() }
                break
            }
        }
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }

    private static func scratchDirectory() throws -> URL {
        let root = URL.applicationSupportDirectory
            .appendingPathComponent("Slate/GitScratch", isDirectory: true)
        try PrivateStorage.ensureDirectory(root)
        let scratch = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateStorage.ensureDirectory(scratch)
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("home", isDirectory: true))
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("tmp", isDirectory: true))
        return scratch
    }

    private static func sandboxProfile(workspace: URL, scratch: URL) -> String {
        func literal(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let workspacePath = workspace.path
        let scratchPath = scratch.path
        let systemRead = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/dev/null", "/dev/urandom",
                          "/Applications/Xcode.app/Contents/Developer", "/Library/Developer/CommandLineTools"]
            .map { "(subpath \(literal($0)))" }.joined(separator: "\n  ")
        // `/usr/bin/git` is an Apple shim on many Macs and transfers to the
        // Xcode or Command Line Tools copy. Permit precisely those system tool
        // paths, but no repository-supplied helper.
        let allowedGitExec = ["/usr/bin/git", "/usr/bin/xcrun",
                              "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
                              "/Library/Developer/CommandLineTools/usr/bin/git"]
            .map { "(literal \(literal($0)))" }.joined(separator: "\n  ")
        return """
        (version 1)
        (import "system.sb")
        (deny default)
        ;; The initial exec from sandbox-exec is the only exec allowed. This
        ;; specifically blocks repo-configured hooks, filters and helpers.
        (allow process-exec
          \(allowedGitExec))
        (allow process-fork)
        (allow signal (target self))
        (allow process-info-pidinfo (target self))
        (allow sysctl-read)
        (allow file-read*
          \(systemRead)
          (subpath \(literal(workspacePath)))
          (subpath \(literal(scratchPath))))
        (allow file-read-metadata file-test-existence
          (path-ancestors \(literal(workspacePath)))
          (path-ancestors \(literal(scratchPath))))
        (allow file-write*
          (subpath \(literal(workspacePath)))
          (subpath \(literal(scratchPath))))
        (deny network*)
        """
    }

    public static func isRepo(_ folder: URL) -> Bool {
        run(["rev-parse", "--is-inside-work-tree"], in: folder)
            .out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public static func currentBranch(_ folder: URL) -> String? {
        let r = run(["rev-parse", "--abbrev-ref", "HEAD"], in: folder)
        let b = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.code == 0 && !b.isEmpty) ? b : nil
    }

    public static func status(_ folder: URL) -> [Change] {
        let r = run(["status", "--porcelain"], in: folder)
        guard r.code == 0 else { return [] }
        return r.out.split(separator: "\n").compactMap { line in
            let s = String(line)
            guard s.count > 3 else { return nil }
            return Change(status: String(s.prefix(2)), path: String(s.dropFirst(3)))
        }
    }

    public static func diff(_ folder: URL, file: String?) -> String {
        var args = ["diff", "--no-color", "--no-ext-diff"]
        if let file { args += ["--", file] }
        let r = run(args, in: folder)
        let staged = run(["diff", "--no-color", "--no-ext-diff", "--cached"] + (file.map { ["--", $0] } ?? []), in: folder)
        let combined = [r.out, staged.out].filter { !$0.isEmpty }.joined(separator: "\n")
        return combined.isEmpty ? "(no changes)" : combined
    }

    @discardableResult
    public static func stageAll(_ folder: URL) -> Bool { run(["add", "-A"], in: folder).code == 0 }

    public static func commit(_ folder: URL, message: String) -> (ok: Bool, output: String) {
        guard stageAll(folder) else {
            return (false, "Git could not stage the workspace safely.")
        }
        let r = run(["commit", "--no-verify", "-m", message], in: folder)
        return (r.code == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @discardableResult
    public static func initRepo(_ folder: URL) -> Bool { run(["init"], in: folder).code == 0 }
}
