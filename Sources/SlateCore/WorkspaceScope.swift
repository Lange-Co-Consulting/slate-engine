import Foundation

public struct WorkspaceScope: Sendable {
    public enum ScopeError: Error, LocalizedError, Equatable {
        case outsideRoot(requested: String, resolved: String)
        public var errorDescription: String? {
            if case let .outsideRoot(req, res) = self { return "Path escapes workspace root: \(req) -> \(res)" }
            return nil
        }
    }

    public let root: URL
    private let rootPath: String   // canonical, no trailing slash
    private let rootPrefix: String // canonical + "/"

    public init(root: URL) {
        let canon = root.standardizedFileURL.resolvingSymlinksInPath()
        self.root = canon
        var p = canon.path
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        self.rootPath = p
        self.rootPrefix = p + "/"
    }

    private func canonicalize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func resolve(_ candidate: String) throws -> URL {
        let raw = URL(fileURLWithPath: candidate, relativeTo: root)
        let resolved = canonicalize(raw)
        let rp = resolved.path
        guard rp == rootPath || rp.hasPrefix(rootPrefix) else {
            throw ScopeError.outsideRoot(requested: candidate, resolved: rp)
        }
        return resolved
    }

    public func contains(_ url: URL) -> Bool {
        let rp = canonicalize(url).path
        return rp == rootPath || rp.hasPrefix(rootPrefix)
    }
}
