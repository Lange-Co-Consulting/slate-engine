import Testing
@testable import SlateFlowCleanup

@Test func styleRoundTrips() {
    for s in CleanupStyle.allCases {
        #expect(CleanupStyle(rawValue: s.rawValue) == s)
    }
}
