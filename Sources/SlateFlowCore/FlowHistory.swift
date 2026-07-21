import Foundation
import SlateCore

/// Dictation history (spec item 11): append-only JSONL in Application Support,
/// plus crash recovery - the raw recording is parked as a WAV between capture
/// stop and successful insert; if Slate dies in between, the next launch finds
/// the file and offers to transcribe it again.
public struct FlowHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var date: Date
    public var raw: String
    public var polished: String
    public var durationSec: Double
    public init(id: UUID = UUID(), date: Date = .now, raw: String,
                polished: String, durationSec: Double) {
        self.id = id; self.date = date; self.raw = raw
        self.polished = polished; self.durationSec = durationSec
    }
}

public enum FlowHistory {
    private static let maxStoreBytes = 2_000_000
    private static let maxRecoveryBytes = 64 * 1_024 * 1_024
    public static var dirURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slate")
    }
    public static var storeURL: URL { dirURL.appendingPathComponent("flow-history.jsonl") }
    public static var recoveryURL: URL { dirURL.appendingPathComponent("flow-recovery.wav") }

    public static func append(_ entry: FlowHistoryEntry) {
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        guard line.count <= maxStoreBytes else { return }
        var data = (try? PrivateStorage.read(from: storeURL, maxBytes: maxStoreBytes)) ?? Data()
        data.append(line)
        if data.count > maxStoreBytes {
            data = Data(data.suffix(maxStoreBytes))
            if let newline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(...newline)
            } else { data = Data() }
        }
        try? PrivateStorage.write(data, to: storeURL)
    }

    /// Newest first, capped.
    public static func load(limit: Int = 50) -> [FlowHistoryEntry] {
        guard let data = try? PrivateStorage.read(from: storeURL, maxBytes: maxStoreBytes),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n")
            .compactMap { try? decoder.decode(FlowHistoryEntry.self, from: Data($0.utf8)) }
            .suffix(max(0, min(limit, 1_000)))
            .reversed()
    }

    // MARK: Crash recovery

    /// Park the raw 16 kHz mono samples while transcribe→insert is in flight.
    public static func parkRecording(_ samples: [Float]) {
        guard samples.count <= (maxRecoveryBytes - 44) / 2 else { return }
        try? PrivateStorage.write(wavData(samples), to: recoveryURL)
    }
    public static func clearParkedRecording() {
        try? FileManager.default.removeItem(at: recoveryURL)
    }
    /// Samples from a previous crash, if any (nil = clean shutdown).
    public static func parkedRecording() -> [Float]? {
        guard let data = try? PrivateStorage.read(from: recoveryURL, maxBytes: maxRecoveryBytes), data.count > 44 else { return nil }
        let body = data.dropFirst(44)   // our own fixed 44-byte header
        var out = [Float](); out.reserveCapacity(body.count / 2)
        var i = body.startIndex
        while i + 1 < body.endIndex {
            let lo = UInt16(body[i]), hi = UInt16(body[i + 1])
            let sample = Int16(bitPattern: lo | (hi << 8))
            out.append(Float(sample) / 32767)
            i += 2
        }
        return out.isEmpty ? nil : out
    }

    /// Minimal 16-bit PCM mono 16 kHz WAV.
    static func wavData(_ samples: [Float]) -> Data {
        let sampleRate: UInt32 = 16_000
        let pcm: [Int16] = samples.map { Int16(max(-1, min(1, $0)) * 32767) }
        let dataSize = UInt32(pcm.count * 2)
        var d = Data()
        func put(_ s: String) { d.append(contentsOf: s.utf8) }
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put("RIFF"); put32(36 + dataSize); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)          // PCM, mono
        put32(sampleRate); put32(sampleRate * 2)            // byte rate
        put16(2); put16(16)                                 // block align, bits
        put("data"); put32(dataSize)
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
