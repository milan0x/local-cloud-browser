import Foundation

final class SecretsManagerService: BaseService {
    // MARK: - Secret Operations

    func listSecrets(region: String? = nil) async throws -> [Secret] {
        let data = try await client.secretsManagerRequest(action: "ListSecrets", region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secretList = json["SecretList"] as? [[String: Any]] else {
            return []
        }
        return secretList.map { Secret(from: $0) }
    }

    func describeSecret(secretId: String) async throws -> SecretDetail {
        let data = try await client.secretsManagerRequest(
            action: "DescribeSecret",
            payload: ["SecretId": secretId]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return SecretDetail(from: json)
    }

    func getSecretValue(secretId: String) async throws -> SecretValue {
        let data = try await client.secretsManagerRequest(
            action: "GetSecretValue",
            payload: ["SecretId": secretId]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return SecretValue(from: json)
    }

    func createSecret(name: String, secretString: String, description: String? = nil) async throws {
        var payload: [String: Any] = [
            "Name": name,
            "SecretString": secretString,
            "ClientRequestToken": UUID().uuidString,
        ]
        if let description, !description.isEmpty {
            payload["Description"] = description
        }
        _ = try await client.secretsManagerRequest(action: "CreateSecret", payload: payload)
    }

    func updateSecret(secretId: String, secretString: String, description: String? = nil) async throws {
        // Update secret value
        _ = try await client.secretsManagerRequest(
            action: "PutSecretValue",
            payload: [
                "SecretId": secretId,
                "SecretString": secretString,
                "ClientRequestToken": UUID().uuidString,
            ]
        )
        // Update description if provided
        if let description {
            _ = try await client.secretsManagerRequest(
                action: "UpdateSecret",
                payload: [
                    "SecretId": secretId,
                    "Description": description,
                ]
            )
        }
    }

    func deleteSecret(secretId: String, forceDelete: Bool = true) async throws {
        var payload: [String: Any] = ["SecretId": secretId]
        if forceDelete {
            payload["ForceDeleteWithoutRecovery"] = true
        }
        _ = try await client.secretsManagerRequest(action: "DeleteSecret", payload: payload)
    }
}
