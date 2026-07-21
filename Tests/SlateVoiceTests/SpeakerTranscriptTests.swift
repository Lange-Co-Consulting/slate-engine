import XCTest
@testable import SlateSTT

final class SpeakerTranscriptTests: XCTestCase {
    func testSpeakerSegmentFormatsStableTimestampAndReadableLabel() {
        let segment = SpeakerTranscriptSegment(speaker: "S2", startSeconds: 125.4,
                                               endSeconds: 130, text: "Local only.")
        XCTAssertEqual(segment.formatted, "[02:05] Speaker 2: Local only.")
    }
}
