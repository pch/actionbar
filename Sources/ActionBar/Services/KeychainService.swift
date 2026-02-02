import Foundation
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

        if status == errSecDuplicateItem {
            let searchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            return SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess
        }

        return status == errSecSuccess
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        // Delete only when the item is permanently inaccessible (e.g., stale code
        // signature after rebuild). Transient errors like errSecInteractionNotAllowed
        // (keychain locked) should not wipe a valid token.
        if status == errSecAuthFailed || status == errSecDecode {
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
