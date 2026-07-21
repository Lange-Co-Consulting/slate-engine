import Foundation
import SlateCore

public struct FileTools: Sendable {
    public let scope: WorkspaceScope
    public static let maxReadBytes = 2 * 1_024 * 1_024
    public static let maxWriteBytes = 2 * 1_024 * 1_024
    public static let maxProcessOutputBytes = 4 * 1_024 * 1_024
    public init(scope: WorkspaceScope) { self.scope = scope }

    public func readFile(path: String, lineRange: ClosedRange<Int>?) throws -> String {
        let url = try scope.resolve(path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw FileToolsError.notRegularFile(path) }
        let size = values.fileSize ?? 0
        guard size <= Self.maxReadBytes else { throw FileToolsError.fileTooLarge(path, size) }
        let content = try String(contentsOf: url, encoding: .utf8)
        guard let lineRange else { return content }
        let lines = content.components(separatedBy: "\n")
        let lo = max(1, lineRange.lowerBound), hi = min(lines.count, lineRange.upperBound)
        guard lo <= hi else { return "" }
        return lines[(lo - 1)...(hi - 1)].joined(separator: "\n")
    }

    /// Lists tracked/searchable files (gitignore-respected) relative to root.
    public func list(glob: String?) throws -> [String] {
        var args = ["--files", "--color=never", "--null"]
        if let glob { args += ["-g", glob] }
        let out = try Self.runRipgrep(args, cwd: scope.root)
        return out.split(separator: "\0").map(String.init).filter { !$0.isEmpty }.sorted().prefix(10_000).map { $0 }
    }

    /// Searches file contents; returns "file:line:col:match" strings (capped).
    public func search(query: String, max: Int = 200) throws -> [String] {
        let cap = Swift.min(Swift.max(1, max), 200)
        let args = ["--vimgrep", "--no-heading", "--color=never", "--max-count", String(cap), "-F", "-e", query, "."]
        let out = try Self.runRipgrep(args, cwd: scope.root)
        return Array(out.split(separator: "\n").map(String.init).prefix(cap))
    }

    // MARK: - ripgrep

    static func ripgrepURL() -> URL {
        if let bundled = Bundle.main.url(forResource: "rg", withExtension: nil) { return bundled }
        return URL(fileURLWithPath: "/opt/homebrew/bin/rg") // dev fallback
    }

    static func runRipgrep(_ args: [String], cwd: URL) throws -> String {
        let p = Process()
        p.executableURL = ripgrepURL()
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try p.run()
        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            data.append(chunk)
            if data.count > maxProcessOutputBytes {
                if p.isRunning { p.terminate() }
                break
            }
        }
        p.waitUntilExit()
        // rg exit code 1 = "no matches" (not an error); 2 = real error.
        if p.terminationStatus > 1 { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum FileToolsError: Error, LocalizedError, Equatable {
    case fileTooLarge(String, Int)
    case notRegularFile(String)
    public var errorDescription: String? {
        switch self {
        case let .fileTooLarge(path, bytes):
            return "Refusing to read \(path): \(bytes) bytes exceeds Slate's \(FileTools.maxReadBytes)-byte limit."
        case let .notRegularFile(path):
            return "Refusing to read non-regular file: \(path)."
        }
    }
}
