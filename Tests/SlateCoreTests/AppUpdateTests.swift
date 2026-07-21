import Foundation
import Testing
import CryptoKit
@testable import SlateCore

@Suite struct AppUpdateTests {
    @Test func comparesMajorMinorPatch() {
        #expect(AppVersion("0.2.0") > AppVersion("0.1.0"))
        #expect(AppVersion("0.1.1") > AppVersion("0.1.0"))
        #expect(AppVersion("1.0.0") > AppVersion("0.9.9"))
        #expect(AppVersion("0.10.0") > AppVersion("0.9.0"))   // numeric, not lexical
        #expect(AppVersion("0.1.0") == AppVersion("0.1.0"))
    }

    @Test func padsMissingComponents() {
        #expect(AppVersion("0.1") == AppVersion("0.1.0"))
        #expect(AppVersion("1") > AppVersion("0.9.9"))
    }

    @Test func buildBreaksTies() {
        #expect(AppVersion("0.1.0", build: 5) > AppVersion("0.1.0", build: 3))
        #expect(AppVersion("0.1.0", build: 3) == AppVersion("0.1.0", build: 3))
        // A higher version wins even with a lower build.
        #expect(AppVersion("0.2.0", build: 1) > AppVersion("0.1.0", build: 99))
    }

    @Test func toleratesNoise() {
        #expect(AppVersion("v0.2.0") == AppVersion("0.2.0"))
        #expect(AppVersion("0.2.0-beta") == AppVersion("0.2.0"))
    }

    @Test func manifestDecodes() throws {
        let json = """
        {"version":"0.2.0","build":3,"notes":"Voice + memory.","dmgURL":"https://example.com/Slate.dmg","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","signature":"","minimumOS":"26.0"}
        """
        let m = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        #expect(m.version == "0.2.0")
        #expect(m.build == 3)
        #expect(m.appVersion == AppVersion("0.2.0", build: 3))
        #expect(m.dmgURL == "https://example.com/Slate.dmg")
    }

    @Test func manifestIsNewerThanRunning() throws {
        let m = UpdateManifest(version: "0.2.0", build: 3, notes: "", dmgURL: "https://x/Slate.dmg", minimumOS: nil)
        #expect(m.isNewer(thanVersion: "0.1.0", build: 1))
        #expect(!m.isNewer(thanVersion: "0.2.0", build: 3))
        #expect(!m.isNewer(thanVersion: "0.3.0", build: 1))
    }

    @Test func signedManifestRejectsTamperingAndInsecureURLs() throws {
        let key = Curve25519.Signing.PrivateKey()
        var manifest = UpdateManifest(version: "1.0.0", build: 1, notes: "safe",
                                      dmgURL: "https://example.com/Slate.dmg",
                                      sha256: String(repeating: "a", count: 64),
                                      minimumOS: "26.0")
        let signature = try key.signature(for: manifest.signingPayload()).base64EncodedString()
        manifest = UpdateManifest(version: manifest.version, build: manifest.build, notes: manifest.notes,
                                  dmgURL: manifest.dmgURL, sha256: manifest.sha256,
                                  signature: signature, minimumOS: manifest.minimumOS)
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        #expect(manifest.isValidSignature(publicKeyBase64: publicKey))
        let tampered = UpdateManifest(version: "1.0.1", build: 1, notes: manifest.notes,
                                      dmgURL: manifest.dmgURL, sha256: manifest.sha256,
                                      signature: signature, minimumOS: manifest.minimumOS)
        #expect(!tampered.isValidSignature(publicKeyBase64: publicKey))
        let insecure = UpdateManifest(version: manifest.version, build: manifest.build, notes: manifest.notes,
                                      dmgURL: "http://example.com/Slate.dmg", sha256: manifest.sha256,
                                      signature: signature, minimumOS: manifest.minimumOS)
        #expect(!insecure.isValidSignature(publicKeyBase64: publicKey))
    }

    @Test func hashesFilesIncrementally() throws {
        let file = URL.temporaryDirectory.appendingPathComponent("slate-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        #expect(try FileIntegrity.sha256(ofFile: file) == FileIntegrity.sha256(of: Data("abc".utf8)))
    }
}
