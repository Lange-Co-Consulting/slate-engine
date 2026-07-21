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
