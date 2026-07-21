import Foundation

/// Debounces raw Fn/Globe flag reports into clean edges. `flagsChanged` fires
/// for arrow/F-keys too (they carry .maskSecondaryFn) and real presses can
/// flicker; callers feed the *flag state* per event and we emit only genuine,
/// stable transitions. Flickers shorter than `debounce` are swallowed - but the
/// LOGICAL state keeps tracking, so a later report that disagrees with what we
/// last emitted still produces the edge (see flickerThatSettlesUpStillEmitsUp).
public struct FnDebouncer {
    public enum Edge: Equatable, Sendable { case down, up }

    private var emitted = false        // last edge we told the caller about
    private var lastEmitAt = -1.0
    private let debounce: Double

    public init(debounce: Double = 0.04) { self.debounce = debounce }

    public mutating func feed(fnDown: Bool, at t: Double) -> Edge? {
        guard fnDown != emitted else { return nil }        // no change vs what caller knows
        guard t - lastEmitAt >= debounce else { return nil } // flicker - hold position
        emitted = fnDown
        lastEmitAt = t
        return fnDown ? .down : .up
    }
}
