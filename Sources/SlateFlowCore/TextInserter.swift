import AppKit
import ApplicationServices
import SlateCore

/// Decides whether the pre-paste clipboard may be restored: only when OUR write
/// is still the newest (nobody else touched the pasteboard since).
public struct ClipboardGuard: Sendable {
    let savedChangeCount: Int
    let ourChangeCount: Int
    public init(savedChangeCount: Int, ourChangeCount: Int) {
        self.savedChangeCount = savedChangeCount
        self.ourChangeCount = ourChangeCount
    }
    public func shouldRestore(currentChangeCount: Int) -> Bool {
        currentChangeCount == ourChangeCount
    }
}

/// 3-tier text insertion into the focused app (spec §2 - the pattern that works
/// across VoiceInk/Handy/OpenSuperWhisper):
///   1) AX selected-text replacement on the focused element (cleanest; skips
///      secure fields),
///   2) clipboard + synthetic ⌘V - old clipboard restored after 1.0 s (Electron
///      pastes late) and only if nobody else wrote meanwhile,
///   3) AppleScript `keystroke` as the last resort.
/// If every tier fails the transcript STAYS on the clipboard (spec item 4).
@MainActor public final class TextInserter {
    public init() {}

    /// `expectedBundleID` is captured when dictation starts. Refuse delivery if
    /// focus moved meanwhile (for example to a login dialog or another app).
    public func insert(_ text: String, expectedBundleID: String? = nil) async -> Bool {
        guard targetMatches(expectedBundleID), !focusedElementIsSecure() else { return false }
        if axInsert(text) { return true }
        guard targetMatches(expectedBundleID), !focusedElementIsSecure() else { return false }
        if await pasteInsert(text) { return true }
        guard targetMatches(expectedBundleID), !focusedElementIsSecure() else { return false }
        return appleScriptInsert(text)
    }

    private func targetMatches(_ expectedBundleID: String?) -> Bool {
        guard let expectedBundleID else { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedBundleID
    }

    // MARK: Tier 1 - Accessibility

    private func axInsert(_ text: String) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(focusedRef, to: AXUIElement.self)

        // Never write into password fields.
        if focusedElementIsSecure(element) { return false }

        // The element must actually accept selected-text writes.
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString,
                                             &settable) == .success, settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            text as CFTypeRef) == .success
    }

    private func focusedElementIsSecure() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return false }
        return focusedElementIsSecure(unsafeDowncast(focusedRef, to: AXUIElement.self))
    }

    private func focusedElementIsSecure(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        return (roleRef as? String) == "AXSecureTextField"
    }

    // MARK: Tier 2 - clipboard + ⌘V

    private func pasteInsert(_ text: String) async -> Bool {
        let pb = NSPasteboard.general
        // Snapshot every representation of the current contents for restore.
        let savedItems: [[String: Data]] = (pb.pasteboardItems ?? []).compactMap { item in
            var copy: [String: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { copy[t.rawValue] = d } }
            return copy.isEmpty ? nil : copy
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Transient marker: clipboard managers should skip this entry.
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ours = pb.changeCount

        guard synthesizeCmdV() else { return false }

        // Restore off the critical path; skip if someone wrote meanwhile.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            let guardCheck = ClipboardGuard(savedChangeCount: ours - 1, ourChangeCount: ours)
            guard guardCheck.shouldRestore(currentChangeCount: pb.changeCount),
                  !savedItems.isEmpty else { return }
            pb.clearContents()
            let items = savedItems.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (t, d) in dict { item.setData(d, forType: NSPasteboard.PasteboardType(t)) }
                return item
            }
            pb.writeObjects(items)
        }
        return true
    }

    private func synthesizeCmdV() -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState),
              let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),   // kVK_ANSI_V
              let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else { return false }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: Tier 3 - AppleScript

    private func appleScriptInsert(_ text: String) -> Bool {
        let target = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        AuditLog.record(.init(category: "apple-event", action: "insert-text", detail: target,
                              approval: "macOS TCC", outcome: err == nil ? "success" : "failed"))
        return err == nil
    }
}
