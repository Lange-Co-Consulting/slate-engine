import Foundation
import CryptoKit

/// A dotted app version ("0.2.0") with a build tiebreaker, compared numerically
/// (so 0.10.0 > 0.9.0, unlike a string compare). Tolerant of a leading "v" and
/// trailing pre-release noise ("0.2.0-beta").
public struct AppVersion: Comparable, Sendable {
    public let components: [Int]
    public let build: Int

    public init(_ version: String, build: Int = 0) {
        // Keep the leading numeric-dotted core; drop "v" and anything after a "-".
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        components = core.split(separator: ".").map { part in
            Int(part.filter(\.isNumber)) ?? 0
        }
        self.build = build
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let n = max(lhs.components.count, rhs.components.count)
        for i in 0..<n {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return a < b }
        }
        return lhs.build < rhs.build
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The update feed's payload - a small JSON the operator hosts (GitHub Releases,
/// S3, any HTTPS URL). Slate fetches it, compares versions, and offers the DMG.
public struct UpdateManifest: Codable, Sendable, Equatable {
    public let version: String
    public let build: Int
    public let notes: String
    public let dmgURL: String
    /// SHA-256 of the exact DMG bytes, lowercase hexadecimal.
    public let sha256: String
    /// Ed25519 signature of `signingPayload()` using Slate's pinned update key.
    public let signature: String
    public var minimumOS: String?

    public init(version: String, build: Int, notes: String, dmgURL: String,
                sha256: String = "", signature: String = "", minimumOS: String?) {
        self.version = version; self.build = build; self.notes = notes
        self.dmgURL = dmgURL; self.sha256 = sha256.lowercased(); self.signature = signature
        self.minimumOS = minimumOS
    }

    public var appVersion: AppVersion { AppVersion(version, build: build) }

    /// True when this manifest describes a build strictly newer than the running one.
    public func isNewer(thanVersion version: String, build: Int) -> Bool {
        appVersion > AppVersion(version, build: build)
    }

    public var hasValidDigest: Bool {
        sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    public var hasSecureURL: Bool {
        guard let url = URL(string: dmgURL) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false &&
            url.user == nil && url.password == nil
    }

    /// Canonical bytes that release tooling signs. JSONEncoder's sorted keys
    /// keeps this stable across platforms and avoids handwritten concatenation.
    public func signingPayload() throws -> Data {
        struct Payload: Codable {
            let version: String; let build: Int; let notes: String
            let dmgURL: String; let sha256: String; let minimumOS: String?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Payload(version: version, build: build, notes: notes,
                                          dmgURL: dmgURL, sha256: sha256,
                                          minimumOS: minimumOS))
    }

    public func isValidSignature(publicKeyBase64: String) -> Bool {
        guard hasValidDigest, hasSecureURL,
              let keyData = Data(base64Encoded: publicKeyBase64), keyData.count == 32,
              let signatureData = Data(base64Encoded: signature), signatureData.count == 64,
              let payload = try? signingPayload(),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        return key.isValidSignature(signatureData, for: payload)
    }
}

public enum FileIntegrity {
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Incremental hashing keeps multi-gigabyte model and DMG verification out
    /// of memory.
    public static func sha256(ofFile url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
