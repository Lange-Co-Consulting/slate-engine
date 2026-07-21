import Foundation
import SlateCore

public struct EditTool: Sendable {
    public let scope: WorkspaceScope
    public let gate: any ApprovalGate
    public let mode: @Sendable () -> PermissionMode
    public let skipPermissions: @Sendable () -> Bool

    public init(scope: WorkspaceScope, gate: any ApprovalGate,
                mode: @escaping @Sendable () -> PermissionMode,
                skipPermissions: @escaping @Sendable () -> Bool = { false }) {
        self.scope = scope; self.gate = gate; self.mode = mode
        self.skipPermissions = skipPermissions
    }

    /// Parse blocks, apply per file atomically (in-memory), gate, then write. Returns a report.
    public func apply(_ blockText: String) async throws -> String {
        let blocks = EditBlockParser.parse(blockText)
        guard !blocks.isEmpty else { return "No edit blocks found." }

        var report: [String] = []
        let byPath = Dictionary(grouping: blocks, by: \.path)

        for (path, group) in byPath {
            let url = try scope.resolve(path)
            let original: String
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { throw FileToolsError.notRegularFile(path) }
                let size = values.fileSize ?? 0
                guard size <= FileTools.maxReadBytes else { throw FileToolsError.fileTooLarge(path, size) }
                original = try String(contentsOf: url, encoding: .utf8)
            } else {
                original = ""
            }
            var buffer = original
            var fails = 0
            var applied = false
            for block in group {
                if let r = EditApplier.applyToBuffer(buffer, block: block) {
                    buffer = r.text; applied = true
                } else {
                    fails += 1
                    if fails >= 2 {
                        report.append("\(path): \(fails) edit(s) failed - needs whole-file rewrite (escalate).")
                        break
                    }
                }
            }
            guard applied, fails < 2 else { continue }
            guard buffer.utf8.count <= FileTools.maxWriteBytes else {
                throw FileToolsError.fileTooLarge(path, buffer.utf8.count)
            }

            let risk = FileChangeRisk.classify(path: path, old: original, new: buffer)
            let requiresApproval = PermissionPolicy.requiresConfirmation(
                mode: mode(), kind: .fileWrite, risk: risk,
                skipPermissions: skipPermissions())
            if requiresApproval {
                let s = LineDiff.stats(old: original, new: buffer)
                let ok = await gate.confirm(ApprovalRequest(
                    kind: .fileWrite,
                    risk: risk,
                    title: "Apply edits to \(path)  (+\(s.added) −\(s.removed))",
                    detail: LineDiff.unified(old: original, new: buffer),
                    scope: path))
                guard ok else {
                    AuditLog.record(.init(category: "tool", action: "edit", detail: path,
                                          approval: "rejected", outcome: "not run"))
                    report.append("\(path): edit rejected by user."); continue
                }
            }
            try writeAtomic(buffer, to: url)
            let approval = requiresApproval ? "approved" : "automatic"
            AuditLog.record(.init(category: "tool", action: "edit", detail: path,
                                  approval: approval, outcome: "success"))
            report.append("\(path): applied.")
        }
        return report.joined(separator: "\n")
    }

    private func writeAtomic(_ content: String, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".slate-\(UUID().uuidString).tmp")
        guard scope.contains(url.deletingLastPathComponent()) else {
            throw WorkspaceScope.ScopeError.outsideRoot(requested: url.path, resolved: url.path)
        }
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
