import Foundation

public struct MemoryBudget: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case ok, warn, critical }

    public let totalBytes: UInt64
    public let modelBytes: UInt64
    public let estimatedKVBytes: UInt64
    public let reserveBytes: UInt64   // kept free for OS + SwiftUI app

    public init(totalBytes: UInt64, modelBytes: UInt64,
                estimatedKVBytes: UInt64, reserveBytes: UInt64) {
        self.totalBytes = totalBytes
        self.modelBytes = modelBytes
        self.estimatedKVBytes = estimatedKVBytes
        self.reserveBytes = reserveBytes
    }

    public var usedEstimate: UInt64 { modelBytes + estimatedKVBytes }

    public var safeLimit: UInt64 {
        totalBytes > reserveBytes ? totalBytes - reserveBytes : 0
    }

    public var status: Status {
        guard safeLimit > 0 else { return .critical }
        if usedEstimate >= safeLimit { return .critical }
        if Double(usedEstimate) >= Double(safeLimit) * 0.9 { return .warn }
        return .ok
    }

    /// Rough q8 KV-cache estimate. Deliberately conservative; refined later.
    /// Heuristic: ~160 KB per context token at this model class with q8 KV.
    public static func estimatedKVBytes(nCtx: Int) -> UInt64 {
        UInt64(max(0, nCtx)) * 160 * 1024
    }

    /// Convenience: build a budget from the live machine.
    public static func current(modelBytes: UInt64, nCtx: Int,
                               reserveBytes: UInt64 = 6 * 1024 * 1024 * 1024) -> MemoryBudget {
        MemoryBudget(totalBytes: ProcessInfo.processInfo.physicalMemory,
                     modelBytes: modelBytes,
                     estimatedKVBytes: estimatedKVBytes(nCtx: nCtx),
                     reserveBytes: reserveBytes)
    }
}
