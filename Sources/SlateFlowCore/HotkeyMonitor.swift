import AppKit
import CoreGraphics

/// System-wide Fn/Globe key capture via a CGEventTap on `flagsChanged`, plus
/// Esc (keyDown) for cancel-while-recording. Research-hardened:
///   • `.maskSecondaryFn` also fires for arrow/F-keys - FnDebouncer tracks the
///     flag STATE and only emits genuine edges;
///   • the tap re-enables itself after `tapDisabledByTimeout` (App Nap);
///   • permissions are preflighted (Accessibility + Input Monitoring) so the
///     tap never half-installs on a TCC-wedged system.
/// `.listenOnly` - we don't swallow Fn; onboarding tells the user to set the
/// Globe key to "Do Nothing".
@MainActor public final class HotkeyMonitor {
    public var onEdge: ((FnDebouncer.Edge) -> Void)?
    public var onEsc: (() -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var debouncer = FnDebouncer()

    public init() {}

    public static func preflight() -> Bool {
        AXIsProcessTrusted() && CGPreflightListenEventAccess()
    }

    /// Fires the system permission prompts (Accessibility, then Input Monitoring).
    public static func requestPermissions() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        _ = CGRequestListenEventAccess()
    }

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.preflight() else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(info).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }, userInfo: info) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Health check for the M3 onboarding banner: tap exists and is enabled.
    public var isAlive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    nonisolated private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                guard let self, let tap = self.tap else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        if type == .flagsChanged {
            let fn = event.flags.contains(.maskSecondaryFn)
            // NOT event.timestamp: on Apple silicon that is mach_absolute_time()
            // in 24 MHz ticks (timebase 125/3 ≈ 41.67 ns/tick), not nanoseconds.
            // Dividing by 1e9 shrank real time ~41.67×, inflating the debouncer's
            // 40 ms flicker window to ~1.67 s — so holds (long) survived but a
            // double-tap (100–200 ms gaps) was swallowed as flicker and never
            // reached hands-free. systemUptime is real monotonic seconds, sampled
            // here on the tap thread (synchronous with the event, ~µs accurate).
            let t = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let edge = self.debouncer.feed(fnDown: fn, at: t) { self.onEdge?(edge) }
            }
        } else if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 { // Esc
            Task { @MainActor [weak self] in self?.onEsc?() }
        }
    }
}
