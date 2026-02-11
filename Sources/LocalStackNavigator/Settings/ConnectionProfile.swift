import Foundation

struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var endpoint: String
    var region: String
    var accessKeyId: String
    var secretAccessKey: String

    /// Only non-sensitive fields are serialized to UserDefaults.
    /// Credentials are stored separately in the Keychain.
    private enum CodingKeys: String, CodingKey {
        case id, name, endpoint, region
    }

    init(
        id: UUID = UUID(),
        name: String = "Default Connection",
        endpoint: String = "http://localhost:4566",
        region: String = "us-east-1",
        accessKeyId: String = "test",
        secretAccessKey: String = "test"
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.region = region
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        region = try container.decode(String.self, forKey: .region)
        // Credentials are hydrated from Keychain after decoding.
        // Fall back to LocalStack defaults so profiles without Keychain entries work.
        accessKeyId = KeychainHelper.defaultAccessKeyId
        secretAccessKey = KeychainHelper.defaultSecretAccessKey
    }
}
