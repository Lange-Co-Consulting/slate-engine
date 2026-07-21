import Foundation

/// Centralized persistence for Slate's private user data.
///
/// Application Support is private at the macOS-account boundary, but explicit
/// modes keep exported backups, migrated homes and permissive umasks from
/// widening access. Symbolic-link destinations are rejected so a tampered
/// store cannot redirect a later write into an unrelated file.
public enum PrivateStorage {
    public enum StorageError: Error, LocalizedError, Equatable {
        case symbolicLink(String)
        case notDirectory(String)
        case notRegularFile(String)
        case fileTooLarge(String, Int, Int)

        public var errorDescription: String? {
            switch self {
            case .symbolicLink(let path): return "Refusing symbolic link in private storage: \(path)"
            case .notDirectory(let path): return "Private storage path is not a directory: \(path)"
            case .notRegularFile(let path): return "Private storage path is not a regular file: \(path)"
            case let .fileTooLarge(path, actual, maximum):
                return "Private storage file is too large: \(path) (\(actual) bytes; max \(maximum))."
            }
        }
    }

    public static let directoryPermissions = 0o700
    public static let filePermissions = 0o600

    public static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try rejectSymbolicLinkComponents(url)
        if fm.fileExists(atPath: url.path) {
            try rejectSymbolicLink(url)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw StorageError.notDirectory(url.path)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: directoryPermissions])
        }
        try fm.setAttributes([.posixPermissions: directoryPermissions], ofItemAtPath: url.path)
    }

    public static func write(_ data: Data, to url: URL, atomic: Bool = true) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: url.path) {
            try rejectSymbolicLink(url)
        }
        try data.write(to: url, options: atomic ? .atomic : [])
        try FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: url.path)
    }

    public static func write(_ string: String, to url: URL, atomic: Bool = true) throws {
        guard let data = string.data(using: .utf8) else { return }
        try write(data, to: url, atomic: atomic)
    }

    /// Reads an app-owned file without following a symbolic link and with a
    /// hard size cap. This prevents a tampered state file from turning a later
    /// load into an accidental read of an unrelated user document.
    public static func read(from url: URL, maxBytes: Int) throws -> Data {
        guard maxBytes >= 0 else { throw StorageError.fileTooLarge(url.path, 0, maxBytes) }
        try rejectSymbolicLinkComponents(url)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        try rejectSymbolicLink(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw StorageError.notRegularFile(url.path) }
        let size = values.fileSize ?? 0
        guard size <= maxBytes else { throw StorageError.fileTooLarge(url.path, size, maxBytes) }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Tighten legacy content without following symlinks. Call once during
    /// bootstrap so files produced by earlier builds are migrated in place.
    public static func hardenTree(_ root: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            try ensureDirectory(root)
            return
        }
        try ensureDirectory(root)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            let permissions = values.isDirectory == true ? directoryPermissions : filePermissions
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private static func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw StorageError.symbolicLink(url.path) }
    }

    private static func rejectSymbolicLinkComponents(_ url: URL) throws {
        let fm = FileManager.default
        // macOS exposes these root-level compatibility aliases as symlinks
        // (`/var` -> `private/var`, for example). They are OS-owned and are
        // needed for `FileManager.temporaryDirectory`; every other link in a
        // private-storage path remains a hard failure.
        let systemCompatibilityLinks = [
            "/var": "private/var",
            "/tmp": "private/tmp",
            "/etc": "private/etc",
        ]
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            if let destination = try? fm.destinationOfSymbolicLink(atPath: current.path),
               systemCompatibilityLinks[current.path] != destination {
                throw StorageError.symbolicLink(current.path)
            }
        }
    }
}
