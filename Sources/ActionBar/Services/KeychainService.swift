import Foundation
import LocalAuthentication
import Security

enum KeychainService {
    private static let service = "com.menuapp.github-actions"
    private static let account = "github-token"

    static func saveToken(_ token: String) -> Bool {
        deleteToken()

        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadToken() -> String? {
        // Use LAContext with interactionNotAllowed to prevent any system prompts.
        // If the keychain ACL doesn't match (e.g. after a rebuild with a new
        // ad-hoc signature), this will fail silently instead of showing a dialog.
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

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // If the item exists but we can't access it (stale ACL from previous build),
        // delete it so the user gets a clean setup view instead of repeated prompts.
        if status != errSecItemNotFound {
            deleteToken()
        }

        return nil
    }

    @discardableResult
    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
