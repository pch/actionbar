import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        "Failed to save token to Keychain"
    }
}

enum KeychainService {
    // Predates the ActionBar name. Changing it would sign out existing users.
    private static let service = "com.menuapp.github-actions"
    private static let account = "github-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func saveToken(_ token: String) throws {
        deleteToken()

        let data = Data(token.utf8)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        var status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            status = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    static func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
