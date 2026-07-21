import Testing
@testable import SlateCore

@Test func fitsRequiresSizePlusMargin() {
    #expect(DiskSpace.fits(requiredBytes: 10, availableBytes: 100, marginBytes: 5))
    #expect(!DiskSpace.fits(requiredBytes: 98, availableBytes: 100, marginBytes: 5))
    #expect(DiskSpace.fits(requiredBytes: 0, availableBytes: 100, marginBytes: 5))   // unknown size → allow
}
