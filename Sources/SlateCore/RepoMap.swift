import Foundation

/// A compact map of the project (files + top-level symbols), injected into the Code
/// system prompt so a small-context local model understands the codebase without
/// reading every file - the local analogue of an IDE's project index.
public enum RepoMap {
    static let skipDirs: Set<String> = [
        "node_modules", ".git", "build", ".build", "dist", ".next", "out",
        ".venv", "venv", "Pods", ".swiftpm", "DerivedData", ".cache", "target", "vendor",
    ]
    static let codeExt: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cpp", "hpp", "cs", "php", "scala", "ex", "exs",
    ]

    public static func build(folder: URL, maxChars: Int = 3000, maxFiles: Int = 400) -> String {
        let fm = FileManager.default
        let scope = WorkspaceScope(root: folder)
        let root = scope.root
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { return "" }
        var lines: [String] = []
        var count = 0
        for case let url as URL in en {
            if skipDirs.contains(url.lastPathComponent) { en.skipDescendants(); continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            if isDir { continue }
            guard scope.contains(url), values?.isRegularFile == true else { continue }
            count += 1
            if count > maxFiles { break }
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let ext = url.pathExtension.lowercased()
            if codeExt.contains(ext), (values?.fileSize ?? .max) <= 512 * 1_024,
               let content = try? String(contentsOf: url, encoding: .utf8) {
                let syms = symbols(in: content)
                lines.append(syms.isEmpty ? rel : "\(rel) - \(syms.prefix(8).joined(separator: ", "))")
            } else if ext != "" {
                lines.append(rel)
            }
        }
        lines.sort()
        var out = "Project structure of \(root.lastPathComponent):\n"
        for line in lines {
            if out.count + line.count + 1 > maxChars { out += "…(truncated)\n"; break }
            out += line + "\n"
        }
        return out
    }

    /// Prepend the repo map to a system prompt (after any project rules).
    public static func augment(systemPrompt base: String, mapFor folder: URL?) -> String {
        guard let folder, case let map = build(folder: folder), !map.isEmpty else { return base }
        return base + "\n\n" + map
    }

    static func symbols(in content: String) -> [String] {
        let pattern = #"(?m)^\s*(?:public |private |internal |export |static |final |open |pub )*\b(func|class|struct|enum|protocol|def|function|interface|type|fn)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = content as NSString
        var names: [String] = []
        var seen = Set<String>()
        for m in re.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let kind = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            let label = "\(kind) \(name)"
            if seen.insert(label).inserted { names.append(label) }
        }
        return names
    }
}
