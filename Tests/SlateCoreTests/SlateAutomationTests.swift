import Foundation
import Testing
@testable import SlateCore

@Suite struct SlateAutomationTests {
    @Test func acceptsOnlyAutomationUUIDURLs() {
        let id = UUID()
        #expect(SlateAutomation.id(from: URL(string: "slate://automation/\(id.uuidString)")!) == id)
        #expect(SlateAutomation.id(from: URL(string: "https://automation/\(id.uuidString)")!) == nil)
        #expect(SlateAutomation.id(from: URL(string: "slate://other/\(id.uuidString)")!) == nil)
        #expect(SlateAutomation.id(from: URL(string: "slate://automation/not-a-uuid")!) == nil)
    }

    @Test func requestAndResponseNamesAreFixedUUIDJSON() {
        let id = UUID()
        #expect(SlateAutomation.requestURL(for: id).lastPathComponent == id.uuidString.lowercased() + ".json")
        #expect(SlateAutomation.responseURL(for: id).lastPathComponent == id.uuidString.lowercased() + ".json")
        #expect(SlateAutomation.requestURL(for: id).deletingLastPathComponent() == SlateAutomation.inbox)
        #expect(SlateAutomation.responseURL(for: id).deletingLastPathComponent() == SlateAutomation.outbox)
    }

    @Test func payloadRoundTrips() throws {
        let request = SlateAutomationRequest(action: .ask, text: "Summarize this")
        let decoded = try JSONDecoder().decode(SlateAutomationRequest.self,
                                               from: JSONEncoder().encode(request))
        #expect(decoded == request)
    }
}
