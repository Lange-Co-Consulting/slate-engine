import Foundation
import Testing
@testable import SlateCore

@Suite struct MemoryStoreTests {
    @Test func addStoresAndReturnsMemory() {
        var s = MemoryStore()
        let m = s.add("Der Nutzer führt eine Consulting GmbH.", source: "Chat")
        #expect(m != nil)
        #expect(s.entries.count == 1)
        #expect(s.entries.first?.text == "Der Nutzer führt eine Consulting GmbH.")
    }

    @Test func exactAndCaseInsensitiveDuplicatesRejected() {
        var s = MemoryStore()
        _ = s.add("Bevorzugt kurze Antworten.", source: nil)
        #expect(s.add("Bevorzugt kurze Antworten.", source: nil) == nil)
        #expect(s.add("bevorzugt KURZE Antworten!", source: nil) == nil)
        #expect(s.entries.count == 1)
    }

    @Test func containmentDuplicatesRejected() {
        var s = MemoryStore()
        _ = s.add("Der Nutzer arbeitet an der App Slate, einem offline Coding-Agenten.", source: nil)
        #expect(s.add("Der Nutzer arbeitet an der App Slate", source: nil) == nil)
        #expect(s.entries.count == 1)
    }

    @Test func capEvictsOldest() {
        var s = MemoryStore()
        for i in 0..<(MemoryStore.cap + 5) {
            _ = s.add("Einzigartige Erinnerung Nummer \(i) mit genug Substanz.", source: nil)
        }
        #expect(s.entries.count == MemoryStore.cap)
        #expect(!s.entries.contains { $0.text.contains("Nummer 0 ") || $0.text.hasSuffix("Nummer 0 mit genug Substanz.") })
    }

    @Test func removeAndRemoveAll() {
        var s = MemoryStore()
        let m = s.add("Mag monochrome UI ohne Blau.", source: nil)!
        _ = s.add("Spricht Deutsch und Englisch.", source: nil)
        s.remove(m.id)
        #expect(s.entries.count == 1)
        s.removeAll()
        #expect(s.entries.isEmpty)
    }

    @Test func promptBlockListsEnabledNewestLimited() {
        var s = MemoryStore()
        _ = s.add("Fakt eins über den Nutzer.", source: nil)
        _ = s.add("Fakt zwei über den Nutzer.", source: nil)
        var disabled = s.entries[0]
        disabled.enabled = false
        s.replace(disabled)
        let block = s.promptBlock()
        #expect(block != nil)
        #expect(block!.contains("Fakt zwei"))
        #expect(!block!.contains("Fakt eins"))
        #expect(s.promptBlock(limit: 0) == nil)
    }

    @Test func promptBlockNilWhenEmpty() {
        #expect(MemoryStore().promptBlock() == nil)
    }

    @Test func sanitizeExtractionAcceptsCleanFact() {
        #expect(MemoryStore.sanitizeExtraction("- \"Der Nutzer heißt Emil.\"") == "Der Nutzer heißt Emil.")
    }

    @Test func sanitizeExtractionRejectsNoneEmptyAndOverlong() {
        #expect(MemoryStore.sanitizeExtraction("NONE") == nil)
        #expect(MemoryStore.sanitizeExtraction("none.") == nil)
        #expect(MemoryStore.sanitizeExtraction("   ") == nil)
        #expect(MemoryStore.sanitizeExtraction(String(repeating: "x", count: 400)) == nil)
    }

    @Test func sanitizeExtractionTakesFirstLine() {
        #expect(MemoryStore.sanitizeExtraction("Der Nutzer mag Espresso.\nUnd noch was.") == "Der Nutzer mag Espresso.")
    }

    @Test func saveLoadRoundtrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-memtest-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("memory.json")
        defer { try? FileManager.default.removeItem(at: dir) }
        var s = MemoryStore()
        _ = s.add("Roundtrip-Fakt über den Nutzer.", source: "Test")
        s.save(to: url)
        let loaded = MemoryStore.load(from: url)
        #expect(loaded.entries.map(\.text) == s.entries.map(\.text))
    }
}
