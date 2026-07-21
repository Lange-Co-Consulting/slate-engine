import Testing
import Foundation
import CryptoKit
@testable import SlateCore

/// The pure entitlement resolution — the security-critical core. No network, no
/// Keychain: given a stored record/trial and "now", what is the user entitled to?
@Suite struct LicensingTests {
    // A fixed clock so grace-window math is deterministic.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func days(_ n: Double) -> TimeInterval { n * 86_400 }

    private func record(status: LicenseStatus, validatedDaysAgo: Double, tier: LicenseTier = .pro) -> LicenseRecord {
        LicenseRecord(key: "K", activationId: "A", organizationId: "O", tier: tier,
                      status: status, activatedAt: now.addingTimeInterval(-days(validatedDaysAgo)),
                      lastValidatedAt: now.addingTimeInterval(-days(validatedDaysAgo)))
    }

    @Test func freeWithNothingStored() {
        let e = LicenseLogic.entitlement(record: nil, trial: nil, now: now, trialDays: 14)
        #expect(e == .free)
        #expect(e.isPro == false)
    }

    @Test func proWhenGrantedWithinGrace() {
        let e = LicenseLogic.entitlement(record: record(status: .granted, validatedDaysAgo: 5),
                                         trial: nil, now: now, trialDays: 14)
        #expect(e == .pro(.pro))
        #expect(e.isPro)
    }

    @Test func founderTierStillPro() {
        let e = LicenseLogic.entitlement(record: record(status: .granted, validatedDaysAgo: 1, tier: .founder),
                                         trial: nil, now: now, trialDays: 14)
        #expect(e == .pro(.founder))
    }

    @Test func polarBenefitIdsResolveExactTierAndRejectUnknownProducts() {
        #expect(LicenseLogic.tier(forBenefitID: "pro", proBenefitID: "pro", founderBenefitID: "founder") == .pro)
        #expect(LicenseLogic.tier(forBenefitID: "founder", proBenefitID: "pro", founderBenefitID: "founder") == .founder)
        #expect(LicenseLogic.tier(forBenefitID: "another-product", proBenefitID: "pro", founderBenefitID: "founder") == nil)
        #expect(LicenseLogic.tier(forBenefitID: "", proBenefitID: "", founderBenefitID: "founder") == nil)
        #expect(LicenseLogic.tier(forBenefitID: "same", proBenefitID: "same", founderBenefitID: "same") == nil)
    }

    @Test func polarActivationResponseDecodesBenefitId() throws {
        let data = Data(#"{"id":"activation","license_key":{"id":"key-id","key":"SLATE_PRO_123","status":"granted","benefit_id":"pro-benefit"}}"#.utf8)
        let response = try JSONDecoder().decode(PolarActivateResponse.self, from: data)
        #expect(response.license_key.benefit_id == "pro-benefit")
    }

    @Test func polarValidationResponseDecodesBenefitId() throws {
        let data = Data(#"{"status":"granted","benefit_id":"founder-benefit"}"#.utf8)
        let response = try JSONDecoder().decode(PolarValidateResponse.self, from: data)
        #expect(response.status == "granted")
        #expect(response.benefit_id == "founder-benefit")
    }

    @Test func paidLicenceRemainsProIndefinitelyOffline() {
        // Connectivity must never be required after a successful paid activation.
        let e = LicenseLogic.entitlement(record: record(status: .granted, validatedDaysAgo: 31),
                                         trial: nil, now: now, trialDays: 14)
        #expect(e == .pro(.pro))
    }

    @Test func revokedIsNeverPro() {
        let e = LicenseLogic.entitlement(record: record(status: .revoked, validatedDaysAgo: 0),
                                         trial: nil, now: now, trialDays: 14)
        #expect(e == .free)
    }

    @Test func expiredIsNeverPro() {
        let e = LicenseLogic.entitlement(record: record(status: .expired, validatedDaysAgo: 0),
                                         trial: nil, now: now, trialDays: 14)
        #expect(e == .free)
    }

    @Test func trialActiveWithinWindow() {
        let trial = TrialRecord(startedAt: now.addingTimeInterval(-days(3)))
        let e = LicenseLogic.entitlement(record: nil, trial: trial, now: now, trialDays: 14)
        #expect(e == .trial(daysLeft: 11))
        #expect(e.isPro)
    }

    @Test func trialExpiresToFree() {
        let trial = TrialRecord(startedAt: now.addingTimeInterval(-days(14)))
        let e = LicenseLogic.entitlement(record: nil, trial: trial, now: now, trialDays: 14)
        #expect(e == .free)
    }

    @Test func validLicenceWinsOverExpiredTrial() {
        let trial = TrialRecord(startedAt: now.addingTimeInterval(-days(90)))   // long dead
        let e = LicenseLogic.entitlement(record: record(status: .granted, validatedDaysAgo: 2),
                                         trial: trial, now: now, trialDays: 14)
        #expect(e == .pro(.pro))
    }

    @Test func revalidateThrottling() {
        let fresh = record(status: .granted, validatedDaysAgo: 0.25)   // ~6h ago
        #expect(LicenseLogic.shouldRevalidate(record: fresh, now: now) == false)
        let stale = record(status: .granted, validatedDaysAgo: 2)      // 2 days ago
        #expect(LicenseLogic.shouldRevalidate(record: stale, now: now) == true)
        #expect(LicenseLogic.shouldRevalidate(record: nil, now: now) == false)
    }

    @Test func capabilityPolicyKeepsLocalFundamentalsFree() {
        #expect(Entitlement.free.allows(.localChat))
        #expect(Entitlement.free.allows(.knowledgeImport))
        #expect(Entitlement.free.allows(.quickAsk))
        #expect(Entitlement.free.allows(.singleFileTranscription))
        #expect(Entitlement.free.allows(.globalSearch))
        #expect(Entitlement.free.allows(.shortcuts))
        #expect(!Entitlement.free.allows(.flow))
        #expect(!Entitlement.free.allows(.localTools))
        #expect(Entitlement.pro(.pro).allows(.localTools))
    }

    @Test func signedOfflineLicenceVerifiesLocally() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = OfflineLicensePayload(
            licenseID: "airgap-001", tier: .founder,
            issuedAt: now.addingTimeInterval(-days(1)),
            deviceIDHash: OfflineLicenseVerifier.deviceHash(for: "install-123"),
            customerName: "Local User"
        )
        let payloadData = try JSONEncoder().encode(payload)
        let document = OfflineLicenseDocument(
            payload: payloadData.base64EncodedString(),
            signature: try privateKey.signature(for: payloadData).base64EncodedString()
        )
        let documentData = try JSONEncoder().encode(document)
        let verified = try OfflineLicenseVerifier.verify(
            documentData: documentData,
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            installationID: "install-123", now: now
        )
        #expect(verified == payload)
    }

    @Test func offlineLicenceRejectsTamperingExpiryAndWrongDevice() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        func document(_ payload: OfflineLicensePayload) throws -> Data {
            let data = try JSONEncoder().encode(payload)
            return try JSONEncoder().encode(OfflineLicenseDocument(
                payload: data.base64EncodedString(),
                signature: try privateKey.signature(for: data).base64EncodedString()
            ))
        }
        let key = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let expired = OfflineLicensePayload(licenseID: "expired", tier: .pro,
                                            issuedAt: now.addingTimeInterval(-days(10)),
                                            expiresAt: now.addingTimeInterval(-1))
        #expect(throws: OfflineLicenseError.expired) {
            try OfflineLicenseVerifier.verify(documentData: document(expired), publicKeyBase64: key,
                                              installationID: "this-mac", now: now)
        }
        let bound = OfflineLicensePayload(licenseID: "bound", tier: .pro, issuedAt: now,
                                          deviceIDHash: OfflineLicenseVerifier.deviceHash(for: "another-mac"))
        #expect(throws: OfflineLicenseError.wrongDevice) {
            try OfflineLicenseVerifier.verify(documentData: document(bound), publicKeyBase64: key,
                                              installationID: "this-mac", now: now)
        }
        var tampered = try JSONDecoder().decode(OfflineLicenseDocument.self, from: document(bound))
        tampered.payload = Data("tampered".utf8).base64EncodedString()
        #expect(throws: OfflineLicenseError.malformedDocument) {
            try OfflineLicenseVerifier.verify(documentData: JSONEncoder().encode(tampered), publicKeyBase64: key,
                                              installationID: "this-mac", now: now)
        }
    }
}
