import Foundation

/// Parses a user-typed dev-server address into a URL, restricted to LOCAL hosts.
/// This powers the code-mode live preview, which is a dev-server viewer - NOT a
/// general web browser - so only loopback targets are ever accepted.
public enum DevServerURL {
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1"]

    /// Accepts "3000", "localhost:3000", "127.0.0.1:8080/path", "http://localhost:5173".
    /// Returns nil for a non-local host, an unsupported scheme, or garbage.
    public static func parse(_ raw: String) -> URL? {
        let s0 = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s0.isEmpty else { return nil }
        // A bare port number → localhost:port.
        if let port = Int(s0), port > 0, port <= 65_535 {
            return URL(string: "http://localhost:\(port)")
        }
        let s = s0.contains("://") ? s0 : "http://" + s0
        guard let comps = URLComponents(string: s),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = comps.host?.lowercased() else { return nil }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))   // strip IPv6 brackets
        guard localHosts.contains(host) else { return nil }
        return comps.url
    }
}
