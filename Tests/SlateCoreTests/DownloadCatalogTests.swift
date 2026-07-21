import Foundation
import Testing
@testable import SlateCore

@Test func catalogEntriesAreWellFormed() {
    #expect(!DownloadCatalog.models.isEmpty)
    let names = Set(DownloadCatalog.models.map(\.fileName))
    #expect(names.count == DownloadCatalog.models.count)   // unique targets
    for m in DownloadCatalog.models {
        #expect(m.url != nil)
        #expect(m.url!.scheme == "https")
        #expect(m.modelCardURL?.scheme == "https")
        #expect(!m.licenseName.isEmpty)
        #expect(m.licenseURL?.scheme == "https")
        #expect(!(m.modelCardURL?.absoluteString.contains("/resolve/") ?? true))
        #expect(m.fileName.hasSuffix(".gguf"))
        #expect(m.bytes > 1_000_000_000)                    // all are multi-GB models
    }
}

@Test func contentRangeTotalParsing() {
    // The exact resume that broke a real download: a 206 whose full total is the
    // number after the slash, NOT expectedContentLength (which is the remaining
    // 9,463,672,987). The stitched file is 9,527,501,472 = the total below.
    #expect(DownloadCatalog.totalBytes(fromContentRange: "bytes 63828485-9527501471/9527501472") == 9_527_501_472)
    #expect(DownloadCatalog.totalBytes(fromContentRange: "bytes 0-99/100") == 100)
    #expect(DownloadCatalog.totalBytes(fromContentRange: "bytes 200-1023/1024 ") == 1024)   // trailing space
    // No usable total → nil, so verification falls back to other authoritative sizes.
    #expect(DownloadCatalog.totalBytes(fromContentRange: nil) == nil)
    #expect(DownloadCatalog.totalBytes(fromContentRange: "bytes 0-99/*") == nil)   // unknown total
    #expect(DownloadCatalog.totalBytes(fromContentRange: "garbage") == nil)
    #expect(DownloadCatalog.totalBytes(fromContentRange: "bytes 0-99/") == nil)
}

@Test func ramFitThresholds() {
    let ram: UInt64 = 24 * 1024 * 1024 * 1024              // 24 GB machine
    #expect(ModelRAMFit.evaluate(fileBytes: 10_000_000_000, physicalRAM: ram) == .comfortable)
    #expect(ModelRAMFit.evaluate(fileBytes: 17_486_174_848, physicalRAM: ram) == .tight)
    #expect(ModelRAMFit.evaluate(fileBytes: 22_000_000_000, physicalRAM: ram) == .tooBig)
    #expect(ModelRAMFit.evaluate(fileBytes: 1, physicalRAM: 0) == .tooBig)
}

@Test func ggufMagicDetection() throws {
    let dir = FileManager.default.temporaryDirectory
    let good = dir.appendingPathComponent("good-\(UUID().uuidString).gguf")
    let bad = dir.appendingPathComponent("bad-\(UUID().uuidString).gguf")
    try Data("GGUF-rest-of-header".utf8).write(to: good)
    try Data("<html>not a model</html>".utf8).write(to: bad)
    defer { try? FileManager.default.removeItem(at: good); try? FileManager.default.removeItem(at: bad) }
    #expect(DownloadCatalog.hasGGUFMagic(good))
    #expect(!DownloadCatalog.hasGGUFMagic(bad))
}

@Test func safeTensorsHeaderDetection() throws {
    let file = URL.temporaryDirectory.appendingPathComponent("tensor-\(UUID().uuidString).safetensors")
    defer { try? FileManager.default.removeItem(at: file) }
    let header = try JSONSerialization.data(withJSONObject: ["tensor": ["dtype": "F32"]])
    var data = Data()
    var length = UInt64(header.count).littleEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(header)
    data.append(Data(repeating: 0, count: 16))
    try data.write(to: file)
    #expect(DownloadCatalog.hasSafeTensorsHeader(file))
    try Data("not a tensor".utf8).write(to: file)
    #expect(!DownloadCatalog.hasSafeTensorsHeader(file))
}
