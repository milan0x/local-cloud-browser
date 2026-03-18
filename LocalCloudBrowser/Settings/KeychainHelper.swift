import Foundation
import Security

enum KeychainHelper {
    private static let service = "LocalCloudBrowser"

    static func save(account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Try to update an existing item first (single Keychain operation).
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        // Item doesn't exist yet — add it.
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Log.error("Keychain save failed for \(account): \(addStatus)", category: "Keychain")
        }
        return addStatus == errSecSuccess
    }

    static func load(account: String) -> Data? {
        loadFromService(service, account: account)
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

    // MARK: - Private helpers

    private static func loadFromService(_ svc: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
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
            Log.error("Keychain load failed for \(account) (service: \(svc)): \(status)", category: "Keychain")
        }
        return nil
    }

    // MARK: - Credential helpers

    static let defaultAccessKeyId = "test"
    static let defaultSecretAccessKey = "test"

    private struct StoredCredentials: Codable {
        let accessKeyId: String
        let secretAccessKey: String
    }

    static func isDefaultCredentials(accessKeyId: String, secretAccessKey: String) -> Bool {
        accessKeyId == defaultAccessKeyId && secretAccessKey == defaultSecretAccessKey
    }

    static func saveCredentials(profileId: UUID, accessKeyId: String, secretAccessKey: String) {
        if isDefaultCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey) {
            // Default credentials don't need Keychain protection.
            // Remove any existing entry (e.g. from a previous version).
            deleteCredentials(profileId: profileId)
            return
        }
        let creds = StoredCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey)
        guard let data = try? JSONEncoder().encode(creds) else {
            Log.error("Failed to encode credentials for profile \(profileId)", category: "Keychain")
            return
        }
        _ = save(account: profileId.uuidString, data: data)
    }

    static func loadCredentials(profileId: UUID) -> (accessKeyId: String, secretAccessKey: String)? {
        guard let data = load(account: profileId.uuidString) else { return nil }
        do {
            let creds = try JSONDecoder().decode(StoredCredentials.self, from: data)
            return (creds.accessKeyId, creds.secretAccessKey)
        } catch {
            Log.error("Failed to decode credentials for profile \(profileId): \(error.localizedDescription)", category: "Keychain")
            return nil
        }
    }

    static func deleteCredentials(profileId: UUID) {
        delete(account: profileId.uuidString)
    }
}
