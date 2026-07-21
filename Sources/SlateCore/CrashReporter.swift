import Foundation

/// A crash macOS recorded for Slate, reduced to an anonymous, submittable report.
public struct CrashReport: Identifiable, Sendable, Equatable {
    public let id: String        // the .ips filename
    public let date: Date
    public let appVersion: String
    public let osVersion: String
    public let summary: String   // e.g. "SIGABRT - EXC_CRASH"
    public let body: String      // allow-listed anonymous text, ready to send

    public init(id: String, date: Date, appVersion: String, osVersion: String, summary: String, body: String) {
        self.id = id; self.date = date; self.appVersion = appVersion
        self.osVersion = osVersion; self.summary = summary; self.body = body
    }
}

/// Reads macOS crash logs for Slate and produces genuinely anonymous reports.
///
/// The report is built by an ALLOW-LIST: only a handful of non-identifying
/// fields are extracted (app/OS version, exception type + signal, termination,
/// and the faulting thread's frame symbols/binary names). The raw .ips is NEVER
/// forwarded - it embeds stable per-device fingerprints (crashReporterKey,
/// deviceIdentifierForVendor, boot/sleep UUIDs) and absolute paths that a
/// deny-list sanitizer would miss. `sanitize` is a final safety net over the
/// already-safe assembled text.
public enum CrashReporter {
    private static let maxReports = 20
    private static let maxReportBytes = 5 * 1_024 * 1_024
    /// Belt-and-suspenders scrub of any residual path/username in assembled text.
    public static func sanitize(_ text: String, username: String, homeDir: String) -> String {
        var s = text
        // /Users/<name> - also the JSON-escaped \/Users\/<name> form used in .ips.
        s = s.replacingOccurrences(of: #"\\?/Users\\?/[^/\\\s"']+"#,
                                   with: "/Users/<user>", options: .regularExpression)
        if !homeDir.isEmpty, homeDir != "/Users/\(username)" {
            s = s.replacingOccurrences(of: homeDir, with: "~")
        }
        // Whole-word username only (≥3 chars) so short names don't shred common
        // words like "signal"/"Metal".
        if username.count >= 3 {
            let escaped = NSRegularExpression.escapedPattern(for: username)
            s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])\(escaped)(?![A-Za-z0-9])",
                                       with: "<user>", options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    public static func scan(directory: URL, since: Date?,
                            username: String, homeDir: String) -> [CrashReport] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey,
                                             .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { return [] }
        let candidates = items.compactMap { url -> (url: URL, modified: Date)? in
            guard url.lastPathComponent.hasPrefix("Slate-"), url.pathExtension == "ips",
                  url.lastPathComponent.range(of: #"^[A-Za-z0-9._-]{1,200}\.ips$"#,
                                              options: .regularExpression) != nil,
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                                 .isRegularFileKey, .isSymbolicLinkKey,
                                                                 .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size >= 0, size <= maxReportBytes else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            guard since.map({ modified > $0 }) ?? true else { return nil }
            return (url, modified)
        }
        .sorted { $0.modified > $1.modified }
        .prefix(maxReports)
        var reports: [CrashReport] = []
        for candidate in candidates {
            let url = candidate.url
            let mtime = candidate.modified
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = extract(raw, fallbackDate: mtime)
            if let since, parsed.date <= since { continue }
            let safe = sanitize(assemble(id: url.lastPathComponent, parsed: parsed),
                                username: username, homeDir: homeDir)
            reports.append(CrashReport(id: url.lastPathComponent, date: parsed.date,
                                       appVersion: parsed.appVersion, osVersion: parsed.osVersion,
                                       summary: parsed.summary, body: safe))
        }
        return reports.sorted { $0.date > $1.date }
    }

    /// Full pipeline for a raw .ips string → anonymous report text. (Also the
    /// unit-test entry point.)
    public static func report(fromRawIPS raw: String, username: String, homeDir: String) -> String {
        sanitize(assemble(id: "report.ips", parsed: extract(raw, fallbackDate: .distantPast)),
                 username: username, homeDir: homeDir)
    }

    // MARK: allow-list extraction

    struct Parsed {
        var date: Date
        var appVersion = "unknown"
        var osVersion = "unknown"
        var bugType = ""
        var summary = "crash"
        var frames: [String] = []
    }

    /// .ips files are two concatenated JSON objects (a header line + a body).
    static func extract(_ raw: String, fallbackDate: Date) -> Parsed {
        var p = Parsed(date: fallbackDate)
        let parts = raw.split(separator: "\n", maxSplits: 1).map(String.init)
        if let d = parts.first?.data(using: .utf8),
           let header = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            p.appVersion = (header["app_version"] as? String) ?? p.appVersion
            p.osVersion = (header["os_version"] as? String) ?? p.osVersion
            p.bugType = (header["bug_type"] as? String) ?? ""
            if let ts = header["timestamp"] as? String, let date = timestamp(ts) { p.date = date }
        }
        guard parts.count > 1, let bd = parts[1].data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: bd) as? [String: Any] else {
            return p
        }
        let exc = body["exception"] as? [String: Any]
        let signal = exc?["signal"] as? String
        let type = exc?["type"] as? String
        let termNS = (body["termination"] as? [String: Any])?["namespace"] as? String
        p.summary = [signal, type, termNS].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
        if p.summary.isEmpty { p.summary = p.bugType.isEmpty ? "crash" : p.bugType }
        // Faulting-thread backtrace, as image-name + symbol only (no paths, no addresses).
        let images = (body["usedImages"] as? [[String: Any]]) ?? []
        if let threads = body["threads"] as? [[String: Any]],
           let crashed = threads.first(where: { ($0["triggered"] as? Bool) == true }) ?? threads.first,
           let frames = crashed["frames"] as? [[String: Any]] {
            for f in frames.prefix(20) {
                let imageIdx = f["imageIndex"] as? Int
                let imageName = imageIdx.flatMap { $0 < images.count ? images[$0]["name"] as? String : nil } ?? "?"
                let symbol = (f["symbol"] as? String) ?? "\(f["imageOffset"] as? Int ?? 0)"
                p.frames.append("\(imageName)  \(symbol)")
            }
        }
        return p
    }

    private static func assemble(id: String, parsed p: Parsed) -> String {
        var out = """
        Slate anonymous crash report
        ----------------------------
        File: \(id)
        Date: \(p.date)
        App version: \(p.appVersion)
        OS: \(p.osVersion)
        Type: \(p.summary)

        Only the fields below are included - no conversation text, file contents,
        absolute paths, device identifiers or account names.
        """
        if !p.frames.isEmpty {
            out += "\n\nFaulting thread:\n"
            out += p.frames.enumerated().map { "  \($0.offset)  \($0.element)" }.joined(separator: "\n")
        }
        return out
    }

    private static func timestamp(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return f.date(from: s) ?? {
            f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return f.date(from: s)
        }()
    }
}
