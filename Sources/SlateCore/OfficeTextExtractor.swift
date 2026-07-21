import Foundation

public enum OfficeTextExtractor {
    public enum Kind: String, Sendable { case docx, xlsx, pptx }
    private static let maxArchiveBytes = 100 * 1_024 * 1_024
    private static let maxEntries = 2_000
    private static let maxEntryBytes = 4 * 1_024 * 1_024
    private static let maxListingBytes = 1 * 1_024 * 1_024
    private static let maxRelevantEntries = 200
    private static let maxExtractedCharacters = 1_000_000
    private static let maxRuntime: TimeInterval = 10

    public static func text(from url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize,
              size <= maxArchiveBytes,
              let kind = Kind(rawValue: url.pathExtension.lowercased()) else { return nil }
        let archive = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let entries = archiveEntries(archive), !entries.isEmpty else { return nil }
        switch kind {
        case .docx:
            let names = entries.filter {
                $0 == "word/document.xml" ||
                $0.range(of: #"^word/(header|footer)[0-9]+\.xml$"#, options: .regularExpression) != nil ||
                ["word/footnotes.xml", "word/endnotes.xml", "word/comments.xml"].contains($0)
            }
            return joinedXMLText(names, archive: archive)
        case .pptx:
            let names = entries.filter {
                $0.range(of: #"^ppt/(slides/slide|notesSlides/notesSlide)[0-9]+\.xml$"#,
                         options: .regularExpression) != nil
            }.sorted(by: naturalOrder)
            return joinedXMLText(names, archive: archive)
        case .xlsx:
            let shared = archiveData(archive, entry: "xl/sharedStrings.xml")
                .map { XMLVisibleTextParser.parse($0, visibleElements: ["t"], paragraphElements: ["si"]) } ?? ""
            let sheets = entries.filter {
                $0.range(of: #"^xl/worksheets/sheet[0-9]+\.xml$"#, options: .regularExpression) != nil
            }.sorted(by: naturalOrder)
            let sheetText = joinedXMLText(sheets, archive: archive) ?? ""
            let parts = [shared, sheetText].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return parts.isEmpty ? nil : String(parts.joined(separator: "\n\n").prefix(maxExtractedCharacters))
        }
    }

    /// Public for deterministic parser tests without needing a binary Office fixture.
    public static func visibleText(fromXML data: Data) -> String {
        XMLVisibleTextParser.parse(
            data,
            visibleElements: ["t", "v"],
            paragraphElements: ["p", "si", "row", "tr"]
        )
    }

    private static func joinedXMLText(_ entries: [String], archive: URL) -> String? {
        var output = ""
        for entry in entries.prefix(maxRelevantEntries) {
            guard let data = archiveData(archive, entry: entry) else { continue }
            let text = visibleText(fromXML: data)
            guard !text.isEmpty else { continue }
            let separator = output.isEmpty ? "" : "\n\n"
            let remaining = maxExtractedCharacters - output.count - separator.count
            guard remaining > 0 else { break }
            output += separator + String(text.prefix(remaining))
        }
        return output.isEmpty ? nil : output
    }

    private static func archiveEntries(_ url: URL) -> [String]? {
        guard let data = runUnzip(["-Z1", url.path], archive: url, maxOutputBytes: maxListingBytes),
              let output = String(data: data, encoding: .utf8) else { return nil }
        let entries = output.split(whereSeparator: \.isNewline).map(String.init)
        return entries.count <= maxEntries ? entries : nil
    }

    private static func archiveData(_ url: URL, entry: String) -> Data? {
        guard !entry.isEmpty, !entry.hasPrefix("/"), !entry.contains("..") else { return nil }
        return runUnzip(["-p", url.path, entry], archive: url, maxOutputBytes: maxEntryBytes)
    }

    private static func runUnzip(_ arguments: [String], archive: URL, maxOutputBytes: Int) -> Data? {
        let archive = archive.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", unzipSandboxProfile(archive: archive), "/usr/bin/unzip"] + arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + maxRuntime, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while let chunk = try? output.fileHandleForReading.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            data.append(chunk)
            if data.count > maxOutputBytes {
                if process.isRunning { process.terminate() }
                return nil
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    private static func unzipSandboxProfile(archive: URL) -> String {
        func literal(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n") + "\""
        }
        let archivePath = archive.path
        let system = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/dev/null", "/dev/urandom"]
            .map { "(subpath \(literal($0)))" }.joined(separator: "\n  ")
        return """
        (version 1)
        (import "system.sb")
        (deny default)
        (allow process-exec (literal \(literal("/usr/bin/unzip"))))
        (allow process-fork)
        (allow signal (target self))
        (allow process-info-pidinfo (target self))
        (allow sysctl-read)
        (allow file-read*
          \(system)
          (literal \(literal(archivePath))))
        (allow file-read-metadata file-test-existence
          (path-ancestors \(literal(archivePath))))
        (deny network*)
        """
    }

    private static func naturalOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}

private final class XMLVisibleTextParser: NSObject, XMLParserDelegate {
    private let visibleElements: Set<String>
    private let paragraphElements: Set<String>
    private var collecting = false
    private var current = ""
    private var lines: [String] = []

    init(visibleElements: Set<String>, paragraphElements: Set<String>) {
        self.visibleElements = visibleElements
        self.paragraphElements = paragraphElements
    }

    static func parse(_ data: Data, visibleElements: Set<String>, paragraphElements: Set<String>) -> String {
        let delegate = XMLVisibleTextParser(visibleElements: visibleElements,
                                            paragraphElements: paragraphElements)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { return "" }
        delegate.flush()
        return delegate.lines.joined(separator: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if visibleElements.contains(local) { collecting = true; current = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if visibleElements.contains(local) {
            let clean = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { lines.append(clean) }
            current = ""; collecting = false
        } else if paragraphElements.contains(local), lines.last != "" {
            lines.append("")
        }
    }

    func flush() {
        while lines.last == "" { lines.removeLast() }
    }
}
