import Foundation
import CryptoKit

/// Pure licensing model + logic. No I/O, no UI - unit-testable in isolation.
/// The app layer (LicenseService) adds Keychain persistence and the Polar network calls.

public enum LicenseTier: String, Codable, Sendable {
    case pro
    case founder
}

public enum LicenseStatus: String, Codable, Sendable {
    case granted     // activated + last check said valid
    case revoked     // server said revoked/refunded/disabled
    case expired     // license validity window ended
}

/// What the user is currently entitled to. `isPro` is the single gate the app reads.
public enum Entitlement: Equatable, Sendable {
    case free
    case trial(daysLeft: Int)
    case pro(LicenseTier)

    public var isPro: Bool {
        switch self {
        case .free: return false
        case .trial, .pro: return true
        }
    }

    public func allows(_ capability: SlateCapability) -> Bool {
        capability.minimumTier == .free || isPro
    }
}

/// One policy for every current and planned feature gate. Local fundamentals stay
/// useful in Free; Pro pays for automation, system-wide workflows and scale.
public enum SlateCapability: String, Codable, CaseIterable, Sendable {
    case localChat
    case knowledgeImport
    case quickAsk
    case singleFileTranscription
    case globalSearch
    case shortcuts
    case flow
    case codeEdits
    case imageGeneration
    case voiceConversation
    case memory
    case modelCompare
    case quickActions
    case watchedLibraries
    case transcriptionPro
    case localTools

    public enum MinimumTier: String, Codable, Sendable { case free, pro }

    public var minimumTier: MinimumTier {
        switch self {
        case .localChat, .knowledgeImport, .quickAsk, .singleFileTranscription,
             .globalSearch, .shortcuts:
            return .free
        case .flow, .codeEdits, .imageGeneration, .voiceConversation, .memory,
             .modelCompare, .quickActions, .watchedLibraries, .transcriptionPro,
             .localTools:
            return .pro
        }
    }
}

/// Persisted activation (stored in Keychain as JSON).
public struct LicenseRecord: Codable, Equatable, Sendable {
    public var key: String
    public var activationId: String
    public var organizationId: String
    public var benefitId: String?
    public var tier: LicenseTier
    public var status: LicenseStatus
    public var activatedAt: Date
    public var lastValidatedAt: Date

    public init(key: String, activationId: String, organizationId: String,
                benefitId: String? = nil, tier: LicenseTier, status: LicenseStatus,
                activatedAt: Date, lastValidatedAt: Date) {
        self.key = key
        self.activationId = activationId
        self.organizationId = organizationId
        self.benefitId = benefitId
        self.tier = tier
        self.status = status
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
    }
}

/// One-time trial marker (stored in Keychain so it can't be reset by clearing defaults).
public struct TrialRecord: Codable, Equatable, Sendable {
    public var startedAt: Date
    public init(startedAt: Date) { self.startedAt = startedAt }
}

/// Pure entitlement resolution. A successfully activated purchase remains usable
/// indefinitely without connectivity. Only an explicit successful validation that
/// reports revoked/expired can remove it.
public enum LicenseLogic {
    /// Resolve the paid tier from Polar's benefit id. Unknown benefits fail closed so a
    /// different licensed product in the same organization cannot unlock Slate.
    public static func tier(forBenefitID benefitID: String,
                            proBenefitID: String,
                            founderBenefitID: String) -> LicenseTier? {
        guard !benefitID.isEmpty,
              !proBenefitID.isEmpty,
              !founderBenefitID.isEmpty,
              proBenefitID != founderBenefitID else { return nil }
        if benefitID == proBenefitID { return .pro }
        if benefitID == founderBenefitID { return .founder }
        return nil
    }

    public static func entitlement(record: LicenseRecord?,
                                   trial: TrialRecord?,
                                   now: Date,
                                   trialDays: Int) -> Entitlement {
        if let r = record {
            switch r.status {
            case .granted:
                return .pro(r.tier)
            case .revoked, .expired:
                break
            }
        }
        if let t = trial {
            let used = now.timeIntervalSince(t.startedAt)
            let remaining = Double(trialDays) * 86_400 - used
            if remaining > 0 {
                let days = max(1, Int((remaining / 86_400).rounded(.up)))
                return .trial(daysLeft: days)
            }
        }
        return .free
    }

    /// True when a fresh online validation should be attempted (throttled to ~daily).
    public static func shouldRevalidate(record: LicenseRecord?, now: Date, everyHours: Double = 24) -> Bool {
        guard let r = record, r.status == .granted else { return false }
        return now.timeIntervalSince(r.lastValidatedAt) >= everyHours * 3600
    }
}

// MARK: - Signed offline licence documents

/// The exact payload stored inside a `.slatelicense` document. The outer document
/// signs the base64-decoded JSON bytes, avoiding fragile JSON canonicalisation.
public struct OfflineLicensePayload: Codable, Equatable, Sendable {
    public var version: Int
    public var licenseID: String
    public var tier: LicenseTier
    public var issuedAt: Date
    public var expiresAt: Date?
    public var deviceIDHash: String?
    public var customerName: String?

    public init(version: Int = 1, licenseID: String, tier: LicenseTier,
                issuedAt: Date, expiresAt: Date? = nil, deviceIDHash: String? = nil,
                customerName: String? = nil) {
        self.version = version
        self.licenseID = licenseID
        self.tier = tier
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.deviceIDHash = deviceIDHash
        self.customerName = customerName
    }
}

public struct OfflineLicenseDocument: Codable, Equatable, Sendable {
    public var payload: String
    public var signature: String

    public init(payload: String, signature: String) {
        self.payload = payload
        self.signature = signature
    }
}

public enum OfflineLicenseError: Error, LocalizedError, Equatable {
    case verifierNotConfigured
    case malformedDocument
    case invalidSignature
    case unsupportedVersion
    case expired
    case wrongDevice

    public var errorDescription: String? {
        switch self {
        case .verifierNotConfigured: return "Offline licence verification isn’t configured yet."
        case .malformedDocument: return "This isn’t a valid Slate licence file."
        case .invalidSignature: return "The licence signature is invalid."
        case .unsupportedVersion: return "This licence file version isn’t supported."
        case .expired: return "This offline licence has expired."
        case .wrongDevice: return "This licence was issued for a different Mac."
        }
    }
}

public enum OfflineLicenseVerifier {
    public static func deviceHash(for installationID: String) -> String {
        SHA256.hash(data: Data(installationID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(documentData: Data, publicKeyBase64: String,
                              installationID: String, now: Date = Date()) throws -> OfflineLicensePayload {
        guard !documentData.isEmpty, documentData.count <= 256 * 1_024 else {
            throw OfflineLicenseError.malformedDocument
        }
        guard let keyData = Data(base64Encoded: publicKeyBase64), !keyData.isEmpty else {
            throw OfflineLicenseError.verifierNotConfigured
        }
        guard let document = try? JSONDecoder().decode(OfflineLicenseDocument.self, from: documentData),
              let payloadData = Data(base64Encoded: document.payload),
              let signatureData = Data(base64Encoded: document.signature),
              let payload = try? JSONDecoder().decode(OfflineLicensePayload.self, from: payloadData),
              !payload.licenseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineLicenseError.malformedDocument
        }
        let publicKey: Curve25519.Signing.PublicKey
        do { publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData) }
        catch { throw OfflineLicenseError.verifierNotConfigured }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw OfflineLicenseError.invalidSignature
        }
        guard payload.version == 1 else { throw OfflineLicenseError.unsupportedVersion }
        if let expiresAt = payload.expiresAt, now > expiresAt { throw OfflineLicenseError.expired }
        if let expectedHash = payload.deviceIDHash,
           expectedHash != deviceHash(for: installationID) { throw OfflineLicenseError.wrongDevice }
        return payload
    }
}

// MARK: - Polar customer-portal license API (public endpoints, no secret needed)

public struct PolarActivateResponse: Decodable, Sendable {
    public struct Key: Decodable, Sendable {
        public let id: String
        public let key: String
        public let status: String
        public let benefit_id: String
    }
    public let id: String          // activation id
    public let license_key: Key
}

public struct PolarValidateResponse: Decodable, Sendable {
    public let status: String      // "granted" | "revoked" | "expired" | ...
    public let benefit_id: String
}

/// Injectable network boundary so LicenseService is testable with a mock.
public protocol PolarLicenseAPI: Sendable {
    /// Activate a key on this device. Returns the activation id + resolved key status.
    func activate(key: String, organizationId: String, label: String) async throws -> PolarActivateResponse
    /// Re-validate an existing activation. Returns the server status string.
    func validate(key: String, organizationId: String, activationId: String) async throws -> PolarValidateResponse
    /// Release this device's activation.
    func deactivate(key: String, organizationId: String, activationId: String) async throws
}

public enum LicenseError: Error, LocalizedError {
    case notConfigured
    case invalidKey
    case unsupportedProduct
    case network(String)
    case activationLimit

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Licensing isn’t configured yet."
        case .invalidKey: return "That licence key wasn’t recognized."
        case .unsupportedProduct: return "That licence key isn’t for Slate Pro or Founder."
        case .activationLimit: return "This licence is already active on the maximum number of Macs."
        case .network(let m): return m
        }
    }
}
