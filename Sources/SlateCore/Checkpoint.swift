import Foundation

/// A point-in-time snapshot of a workspace's text files, so autonomous edits can be
/// reverted with one click. Stored on disk (not in memory) under Application Support.
public struct CheckpointInfo: Identifiable, Equatable, Sendable {
    public let id: String          // timestamp-based dir name
    public let label: String
    public let createdAt: Date
    public let fileCount: Int
    public let dir: URL
}

public enum Checkpoints {
    static let skipDirs = RepoMap.skipDirs
    static let maxFileBytes = 256 * 1024
    static let maxFiles = 600

    private static var rootDir: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Slate/checkpoints", isDirectory: true)
    }

    static func baseDir(key: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_") )
        let safe = key.unicodeScalars.map { allowed.contains($0) ? String($0) : "_\(String($0.value, radix: 16))_" }.joined()
        return rootDir.appendingPathComponent(String(safe.prefix(256)), isDirectory: true)
    }

    /// Snapshot all tracked text files under `scope` into a new checkpoint for `key`.
    @discardableResult
    public static func snapshot(scope: WorkspaceScope, key: String, label: String, now: Date) -> CheckpointInfo? {
        let fm = FileManager.default
        let id = "\(Int(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
        let dir = baseDir(key: key).appendingPathComponent(id, isDirectory: true)
        let filesDir = dir.appendingPathComponent("files", isDirectory: true)
        do { try PrivateStorage.ensureDirectory(filesDir) }
        catch { return nil }

        let rels = trackedFiles(scope.root)
        var manifest: [String] = []
        for rel in rels {
            guard let src = try? scope.resolve(rel),
                  let values = try? src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size <= maxFileBytes,
                  let data = try? Data(contentsOf: src, options: .mappedIfSafe) else { continue }
            let dst = filesDir.appendingPathComponent(rel)
            if (try? PrivateStorage.write(data, to: dst)) != nil { manifest.append(rel) }
        }
        guard !manifest.isEmpty else { try? fm.removeItem(at: dir); return nil }
        try? PrivateStorage.write(manifest.joined(separator: "\n"),
                                  to: dir.appendingPathComponent("manifest.txt"))
        try? PrivateStorage.write(String(label.prefix(500)), to: dir.appendingPathComponent("label.txt"))
        return CheckpointInfo(id: id, label: label, createdAt: now, fileCount: manifest.count, dir: dir)
    }

    public static func list(key: String) -> [CheckpointInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: baseDir(key: key),
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return dirs.compactMap { d -> CheckpointInfo? in
            guard let values = try? d.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let manifestData = try? PrivateStorage.read(from: d.appendingPathComponent("manifest.txt"), maxBytes: 1_000_000),
                  let ms = String(data: manifestData, encoding: .utf8) else { return nil }
            let count = ms.split(separator: "\n").count
            let label = (try? PrivateStorage.read(from: d.appendingPathComponent("label.txt"), maxBytes: 4_096))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "Checkpoint"
            let timestampPart = d.lastPathComponent.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            let ts = Double(timestampPart).map { $0 / 1000 } ?? 0
            return CheckpointInfo(id: d.lastPathComponent, label: label,
                                  createdAt: Date(timeIntervalSince1970: ts), fileCount: count, dir: d)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Restore a checkpoint: rewrite snapshotted files and delete tracked files that
    /// did not exist in the snapshot (a true revert).
    @discardableResult
    public static func restore(_ info: CheckpointInfo, scope: WorkspaceScope) -> Bool {
        let fm = FileManager.default
        let checkpointScope = WorkspaceScope(root: rootDir)
        guard checkpointScope.contains(info.dir) else { return false }
        let filesDir = info.dir.appendingPathComponent("files", isDirectory: true)
        guard let manifestData = try? PrivateStorage.read(from: info.dir.appendingPathComponent("manifest.txt"), maxBytes: 1_000_000),
              let ms = String(data: manifestData, encoding: .utf8) else { return false }
        let entries = ms.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.count <= maxFiles, Set(entries).count == entries.count else { return false }

        let sourceScope = WorkspaceScope(root: filesDir)
        var validated: [(relative: String, source: URL, destination: URL)] = []
        for rel in entries {
            guard isSafeRelativePath(rel),
                  let source = try? sourceScope.resolve(rel),
                  let destination = try? scope.resolve(rel),
                  fm.fileExists(atPath: source.path),
                  let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size <= maxFileBytes else { return false }
            validated.append((rel, source, destination))
        }
        let snapshotted = Set(entries)

        // Delete files created after the snapshot.
        for rel in trackedFiles(scope.root) where !snapshotted.contains(rel) {
            guard let destination = try? scope.resolve(rel) else { return false }
            try? fm.removeItem(at: destination)
        }
        // Restore snapshotted content.
        for item in validated {
            guard let data = try? PrivateStorage.read(from: item.source, maxBytes: maxFileBytes) else { return false }
            do {
                try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: item.destination, options: .atomic)
            } catch { return false }
        }
        return true
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = NSString(string: path).pathComponents
        return !components.contains("..") && !components.contains(".") && !components.contains("")
    }

    /// Relative paths of tracked (ignore-filtered, reasonably sized) files. Resolves
    /// symlinks on both sides so the /var↔/private/var alias doesn't break relativization.
    static func trackedFiles(_ root: URL) -> [String] {
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        for case let url as URL in en {
            if skipDirs.contains(url.lastPathComponent) { en.skipDescendants(); continue }
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            if vals?.isDirectory == true { continue }
            guard vals?.isRegularFile == true,
                  let size = vals?.fileSize, size <= maxFileBytes else { continue }
            let p = url.resolvingSymlinksInPath().path
            guard p.hasPrefix(prefix) else { continue }
            out.append(String(p.dropFirst(prefix.count)))
            if out.count >= maxFiles { break }
        }
        return out
    }
}
