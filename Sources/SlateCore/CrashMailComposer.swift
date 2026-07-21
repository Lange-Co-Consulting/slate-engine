import Foundation

/// Builds a pre-filled `mailto:` URL for an anonymous crash report. The report
/// body is already allow-listed + sanitized by `CrashReporter`; this only frames
/// and length-caps it so the user's mail client can open it. Nothing is sent here.
public enum CrashMailComposer {
    public static let maxURLLength = 8000    // safe mailto length across mail clients

    public static func mailtoURL(_ report: CrashReport, to recipient: String) -> URL? {
        let subject = "Slate crash report - \(report.appVersion) (\(report.summary))"
        var body = report.body + "\n\n(Sent from Slate. You can edit or delete anything before sending.)"
        // Reserve room for the recipient + subject + percent-encoding blow-up.
        let budget = maxURLLength - recipient.count - subject.count - 64
        if body.count > budget, budget > 0 {
            body = String(body.prefix(max(budget - 40, 0))) + "\n\n[truncated - full log in Console.app]"
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents encodes spaces as "+" in queries; mail clients want %20.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%20")
        return components.url
    }
}
