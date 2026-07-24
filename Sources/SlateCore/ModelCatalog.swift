import Foundation

public struct ModelEntry: Sendable, Equatable, Identifiable {
    public let url: URL
    public let bytes: Int64
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public init(url: URL, bytes: Int64 = 0) { self.url = url; self.bytes = bytes }
}

public enum ModelCatalog {
    /// Default GGUF search roots (user's existing stores + common download spots).
    /// Deliberately NOT ~/Downloads (or Desktop/Documents): those are TCC-protected,
    /// so scanning them fires a macOS privacy-consent dialog at launch - which
    /// automation can't dismiss and which is hidden over screen sharing. All of
    /// Slate's own downloads land in ~/Models, and any other model can be added via
    /// "Choose file…" (a user-picked, security-scoped URL that needs no folder grant).
    public static func defaultDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Models"),
            home.appendingPathComponent(".lmstudio/models"),
            home.appendingPathComponent(".cache/lm-studio/models"),
        ]
    }

    /// `excluding` roots are pruned from the scan: their GGUFs are parts of some
    /// OTHER kind of model (e.g. the image-generation bundles - diffusion
    /// transformers and their text encoders), not loadable chat models.
    public static func scan(directories: [URL], excluding excludedRoots: [URL] = []) -> [ModelEntry] {
        let excluded = excludedRoots.map { $0.resolvingSymlinksInPath().path + "/" }
        var seen = Set<String>()
        var found: [ModelEntry] = []
        for dir in directories {
            guard let en = FileManager.default.enumerator(at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in en where url.pathExtension == "gguf" {
                // Multimodal projector files are companions to a model, not chat models themselves.
                guard !isMMProj(url) else { continue }
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let key = url.resolvingSymlinksInPath().path
                guard !excluded.contains(where: { key.hasPrefix($0) }) else { continue }
                guard seen.insert(key).inserted else { continue }
                let bytes = values.fileSize.map(Int64.init) ?? 0
                found.append(ModelEntry(url: url, bytes: bytes))
            }
        }
        return collapseShards(found).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// llama.cpp splits a large model into `<name>-00001-of-00003.gguf` shards. Every
    /// shard is itself a valid .gguf, so a plain scan listed one 100 GB model as three
    /// separate entries — which also reads as duplicates. Keep only the FIRST shard
    /// (llama.cpp loads the whole set from it) and report the set's summed size.
    static func collapseShards(_ entries: [ModelEntry]) -> [ModelEntry] {
        var totals: [String: Int64] = [:]        // set key -> summed bytes
        var firsts: [String: ModelEntry] = [:]   // set key -> the 00001 shard
        var singles: [ModelEntry] = []
        for e in entries {
            guard let s = shardInfo(e.url) else { singles.append(e); continue }
            let setKey = e.url.deletingLastPathComponent().path + "/" + s.stem
            totals[setKey, default: 0] += e.bytes
            if s.index == 1 { firsts[setKey] = e }
        }
        var collapsed = singles
        for (setKey, total) in totals {
            // First shard missing (interrupted download): list nothing rather than an
            // entry that cannot load.
            guard let first = firsts[setKey] else { continue }
            collapsed.append(ModelEntry(url: first.url, bytes: total))
        }
        return collapsed
    }

    /// Parse `…-00002-of-00005.gguf` into (stem before the shard suffix, 2).
    /// nil when the name is not a shard.
    static func shardInfo(_ url: URL) -> (stem: String, index: Int)? {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        guard parts.count >= 4, parts[parts.count - 2] == "of",
              let idx = Int(parts[parts.count - 3]), let total = Int(parts[parts.count - 1]),
              total > 1, idx >= 1, idx <= total else { return nil }
        let stem = parts[0..<(parts.count - 3)].joined(separator: "-")
        guard !stem.isEmpty else { return nil }
        return (stem, idx)
    }

    /// True for a multimodal projector ("mmproj") GGUF - the companion that adds vision to a model.
    public static func isMMProj(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().contains("mmproj")
    }

    /// Find the vision projector that pairs with a given model: a sibling `mmproj*.gguf`
    /// in the same directory. Returns nil for text-only models. A projector is only
    /// paired if its filename shares a distinctive name token with the model - so with
    /// several VLMs in one folder, a text model (or a different VLM) never gets the wrong
    /// projector. A lone, generically-named projector (e.g. `mmproj-model-f16.gguf`) is
    /// still paired as the single-VLM case.
    public static func mmproj(for model: URL) -> URL? {
        let dir = model.deletingLastPathComponent()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let projectors = items.filter { $0.pathExtension == "gguf" && isMMProj($0) }
        guard !projectors.isEmpty else { return nil }
        let want = nameTokens(model.lastPathComponent)
        let scored = projectors.map { ($0, nameTokens($0.lastPathComponent).intersection(want).count) }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        // No name overlap with any projector: only accept a lone, generic projector.
        if projectors.count == 1, nameTokens(projectors[0].lastPathComponent).isEmpty { return projectors[0] }
        return nil
    }

    /// Distinctive lowercased name tokens (drops separators, quant/format noise) used
    /// to match a model to its projector.
    private static func nameTokens(_ name: String) -> Set<String> {
        let stop: Set<String> = ["mmproj", "model", "gguf", "it", "instruct", "f16", "bf16", "f32",
                                 "q2", "q3", "q4", "q5", "q6", "q8", "k", "s", "m", "l", "xs", "xxs"]
        let parts = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { !stop.contains($0) && $0.count > 1 })
    }
}
