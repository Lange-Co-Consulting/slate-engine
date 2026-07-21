import Testing
import Foundation
@testable import SlateCore

private func tmp(_ name: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

// MARK: RepoMap

@Test func repoMapListsFilesAndSymbols() throws {
    let dir = try tmp("slate-repomap"); defer { try? FileManager.default.removeItem(at: dir) }
    try "import Foundation\nstruct Foo {}\nfunc bar() {}\n".write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    try "junk".write(to: dir.appendingPathComponent("node_modules/x.js"), atomically: true, encoding: .utf8)

    let map = RepoMap.build(folder: dir)
    #expect(map.contains("A.swift"))
    #expect(map.contains("struct Foo"))
    #expect(map.contains("func bar"))
    #expect(!map.contains("node_modules"))   // ignored
}

@Test func repoMapSymbolsExtract() {
    let syms = RepoMap.symbols(in: "public func hello() {}\nclass Big {}\nenum E {}")
    #expect(syms.contains("func hello"))
    #expect(syms.contains("class Big"))
    #expect(syms.contains("enum E"))
}

// MARK: Checkpoints

@Test func checkpointSnapshotAndRestore() throws {
    let dir = try tmp("slate-ckpt"); defer { try? FileManager.default.removeItem(at: dir) }
    let scope = WorkspaceScope(root: dir)
    let keep = dir.appendingPathComponent("keep.txt")
    try "original".write(to: keep, atomically: true, encoding: .utf8)

    let key = "test-\(UUID().uuidString)"
    let cp = Checkpoints.snapshot(scope: scope, key: key, label: "before", now: Date(timeIntervalSince1970: 1000))
    #expect(cp != nil)
    defer { try? FileManager.default.removeItem(at: Checkpoints.baseDir(key: key)) }

    // Mutate: change a file + create a new one.
    try "changed".write(to: keep, atomically: true, encoding: .utf8)
    try "new".write(to: dir.appendingPathComponent("added.txt"), atomically: true, encoding: .utf8)

    #expect(Checkpoints.restore(cp!, scope: scope))
    #expect(try String(contentsOf: keep, encoding: .utf8) == "original")       // reverted
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("added.txt").path))  // removed

    #expect(Checkpoints.list(key: key).count == 1)
}

@Test func checkpointRejectsTamperedTraversalManifestBeforeWriting() throws {
    let dir = try tmp("slate-ckpt-target"); defer { try? FileManager.default.removeItem(at: dir) }
    let outside = dir.deletingLastPathComponent().appendingPathComponent("slate-ckpt-outside-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: outside) }
    try "outside".write(to: outside, atomically: true, encoding: .utf8)
    try "inside".write(to: dir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

    let key = "test-\(UUID().uuidString)"
    let cp = try #require(Checkpoints.snapshot(scope: WorkspaceScope(root: dir), key: key,
                                               label: "before", now: Date(timeIntervalSince1970: 2000)))
    defer { try? FileManager.default.removeItem(at: Checkpoints.baseDir(key: key)) }
    try "../../\(outside.lastPathComponent)".write(
        to: cp.dir.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)

    #expect(!Checkpoints.restore(cp, scope: WorkspaceScope(root: dir)))
    #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
    #expect(try String(contentsOf: dir.appendingPathComponent("keep.txt"), encoding: .utf8) == "inside")
}

// MARK: Git

@Test func gitStatusAndCommit() throws {
    let dir = try tmp("slate-git"); defer { try? FileManager.default.removeItem(at: dir) }
    guard Git.initRepo(dir) else { return }   // skip if git unavailable
    _ = Git.run(["config", "user.email", "t@t.t"], in: dir)
    _ = Git.run(["config", "user.name", "T"], in: dir)
    #expect(Git.isRepo(dir))

    try "hello".write(to: dir.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
    let st = Git.status(dir)
    #expect(st.contains { $0.path == "f.txt" })

    let r = Git.commit(dir, message: "init")
    #expect(r.ok)
    #expect(Git.status(dir).isEmpty)          // clean after commit
    #expect(Git.currentBranch(dir) != nil)
}

// MARK: Handoff

@Test func handoffMarkdownFormat() {
    let md = Handoff.markdown(
        title: "Login page",
        folder: "/Users/x/Proj",
        messages: [ChatMessage(role: .user, content: "add login"),
                   ChatMessage(role: .assistant, content: "<think>plan</think>Done.")],
        changedFiles: ["src/Login.swift"])
    #expect(md.contains("# Slate handoff"))
    #expect(md.contains("src/Login.swift"))
    #expect(md.contains("**User:** add login"))
    #expect(md.contains("Done."))
    #expect(!md.contains("plan"))   // reasoning stripped
}
