import Foundation
import Security

enum KeychainHelper {
    private static let service = "LocalStackNavigator"

    static func save(account: String, data: Data) -> Bool {
        // Delete any existing item first to avoid duplicates.
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.error("Keychain save failed for \(account): \(status)", category: "Keychain")
        }
        return status == errSecSuccess
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        }
        if status != errSecItemNotFound {
            Log.error("Keychain load failed for \(account): \(status)", category: "Keychain")
        }
        return nil
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Credential helpers

    private struct StoredCredentials: Codable {
        let accessKeyId: String
        let secretAccessKey: String
    }

    static func saveCredentials(profileId: UUID, accessKeyId: String, secretAccessKey: String) {
        let creds = StoredCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
        guard let data = try? JSONEncoder().encode(creds) else {
            Log.error("Failed to encode credentials for profile \(profileId)", category: "Keychain")
            return
        }
        _ = save(account: profileId.uuidString, data: data)
    }

    static func loadCredentials(profileId: UUID) -> (accessKeyId: String, secretAccessKey: String)? {
        guard let data = load(account: profileId.uuidString),
              let creds = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            return nil
        }
        return (creds.accessKeyId, creds.secretAccessKey)
    }

    static func deleteCredentials(profileId: UUID) {
        delete(account: profileId.uuidString)
    }
}
