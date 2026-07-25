import Foundation
import Security
import LocalAuthentication

/// Minimal Keychain wrapper for Slate's stored secrets - cloud API keys (one per
/// provider id), licence records, and the installation id - kept under one generic
/// password service. Values are never written to UserDefaults or a settings export.
///
/// Public because it is shared infrastructure: the app stores cloud keys with it
/// and the (private) licensing layer stores licence records with it, under the same
/// service so a single "Delete all data" clears everything.
public enum KeychainStore {
    private static let service = "com.langeundco.slate.cloud"

    public static func set(_ value: String, account: String) {
        delete(account: account)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// What a read actually found.
    ///
    /// `get` collapsed every failure to nil, and two callers then read "I could not get it" as "it is
    /// not there" and wrote a replacement: the Slate Remote pairing key, and the licence installation
    /// id. Both replacements are destructive — a new PSK invalidates every paired phone, a new
    /// installation id looks like a different machine to the licence server.
    ///
    /// And the failure is not hypothetical. macOS binds a Keychain item's ACL to the *signing
    /// identity*, so re-signing the app makes every read fail until the user allows it: a Developer
    /// ID certificate renewal does it, and so does replacing a self-signed development build with a
    /// released one. That is exactly how it was found.
    public enum Read: Equatable {
        case found(String)
        case missing
        /// The item exists but this build may not read it right now — a denied ACL, a locked
        /// keychain, a prompt the user dismissed. Never overwrite on this.
        case unavailable(OSStatus)
    }

    public static func read(account: String) -> Read {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return .unavailable(status)
            }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable(status)
        }
    }

    /// Convenience for the many callers that genuinely cannot tell the two apart — an absent API key
    /// and an unreadable one both mean "this provider is not usable right now". Anything that would
    /// *write* on a nil must use `read` instead.
    public static func get(account: String) -> String? {
        let context = LAContext()
        // Startup must remain local and responsive. If a legacy Keychain item's
        // ACL would require a dialog, report it as unavailable rather than
        // blocking the app before its first window can appear.
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether the store is readable at all for this account — used to tell "you have not set this
    /// up" apart from "macOS will not let this build read what you set up".
    public static func isUnavailable(account: String) -> Bool {
        if case .unavailable = read(account: account) { return true }
        return false
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Remove every Slate credential (cloud providers, licence records and the
    /// installation id). Used only by the explicit “Delete all data” action.
    public static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
