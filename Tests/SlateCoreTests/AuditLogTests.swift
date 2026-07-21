import Foundation
import Testing
@testable import SlateCore

@Test func auditEntryRoundTrips() throws {
    let entry = AuditEntry(category: "tool", action: "run_command", detail: "swift test",
                           approval: "approved", outcome: "success", now: Date(timeIntervalSince1970: 1))
    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(AuditEntry.self, from: data)
    #expect(decoded == entry)
}
