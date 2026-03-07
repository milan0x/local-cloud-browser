import Foundation

final class KMSService: BaseService {
    // MARK: - Key Operations

    func listKeys(region: String? = nil) async throws -> [KMSKey] {
        let data = try await client.kmsRequest(action: "ListKeys", region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = json["Keys"] as? [[String: Any]] else {
            return []
        }
        // ListKeys only returns KeyId + KeyArn — enrich with DescribeKey
        return try await withThrowingTaskGroup(of: KMSKey?.self) { group in
            for keyEntry in keys {
                let keyId = keyEntry["KeyId"] as? String ?? ""
                group.addTask {
                    try await self.describeKey(keyId: keyId)
                }
            }
            var result: [KMSKey] = []
            for try await key in group {
                if let key { result.append(key) }
            }
            return result
        }
    }

    func describeKey(keyId: String) async throws -> KMSKey {
        let data = try await client.kmsRequest(
            action: "DescribeKey",
            payload: ["KeyId": keyId]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["KeyMetadata"] as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return KMSKey(from: metadata)
    }

    func createKey(description: String, keyUsage: String, keySpec: String) async throws {
        var payload: [String: Any] = [
            "KeyUsage": keyUsage,
            "KeySpec": keySpec,
        ]
        if !description.isEmpty {
            payload["Description"] = description
        }
        _ = try await client.kmsRequest(action: "CreateKey", payload: payload)
    }

    func scheduleKeyDeletion(keyId: String, pendingDays: Int = 7) async throws {
        _ = try await client.kmsRequest(
            action: "ScheduleKeyDeletion",
            payload: [
                "KeyId": keyId,
                "PendingWindowInDays": pendingDays,
            ]
        )
    }

    func enableKey(keyId: String) async throws {
        _ = try await client.kmsRequest(
            action: "EnableKey",
            payload: ["KeyId": keyId]
        )
    }

    func disableKey(keyId: String) async throws {
        _ = try await client.kmsRequest(
            action: "DisableKey",
            payload: ["KeyId": keyId]
        )
    }

    // MARK: - Alias Operations

    func listAliases(keyId: String? = nil) async throws -> [KMSAlias] {
        var payload: [String: Any] = [:]
        if let keyId {
            payload["KeyId"] = keyId
        }
        let data = try await client.kmsRequest(action: "ListAliases", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let aliases = json["Aliases"] as? [[String: Any]] else {
            return []
        }
        return aliases.map { KMSAlias(from: $0) }
    }

    func createAlias(aliasName: String, targetKeyId: String) async throws {
        _ = try await client.kmsRequest(
            action: "CreateAlias",
            payload: [
                "AliasName": aliasName,
                "TargetKeyId": targetKeyId,
            ]
        )
    }

    func deleteAlias(aliasName: String) async throws {
        _ = try await client.kmsRequest(
            action: "DeleteAlias",
            payload: ["AliasName": aliasName]
        )
    }

    // MARK: - Key Policy

    func getKeyPolicy(keyId: String) async throws -> String {
        let data = try await client.kmsRequest(
            action: "GetKeyPolicy",
            payload: [
                "KeyId": keyId,
                "PolicyName": "default",
            ]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let policy = json["Policy"] as? String else {
            return ""
        }
        return policy
    }
}
