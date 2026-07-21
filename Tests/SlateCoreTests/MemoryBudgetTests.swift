import Testing
@testable import SlateCore

private let GB: UInt64 = 1024 * 1024 * 1024

@Test func okWhenWellUnderSafeLimit() {
    let b = MemoryBudget(totalBytes: 24 * GB, modelBytes: 15 * GB,
                         estimatedKVBytes: 1 * GB, reserveBytes: 5 * GB)
    #expect(b.status == .ok)            // used 16 vs safe 19
}

@Test func warnNearLimit() {
    let b = MemoryBudget(totalBytes: 24 * GB, modelBytes: 17 * GB,
                         estimatedKVBytes: 1 * GB, reserveBytes: 5 * GB)
    #expect(b.status == .warn)          // used 18 vs safe 19 -> >=90%
}

@Test func criticalWhenOverSafeLimit() {
    let b = MemoryBudget(totalBytes: 24 * GB, modelBytes: 18 * GB,
                         estimatedKVBytes: 2 * GB, reserveBytes: 5 * GB)
    #expect(b.status == .critical)      // used 20 vs safe 19
}

@Test func estimateKVScalesWithContext() {
    let small = MemoryBudget.estimatedKVBytes(nCtx: 8_192)
    let big = MemoryBudget.estimatedKVBytes(nCtx: 32_768)
    #expect(big > small)
}
