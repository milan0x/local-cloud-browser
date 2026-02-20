import Foundation

struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    static let defaultHealthPath = "_localstack/health"
    static let defaultS3Domain = "s3.localhost.localstack.cloud"
    static let defaultApiGatewayDomain = "execute-api.localhost.localstack.cloud"

    var id: UUID
    var name: String
    var endpoint: String
    var region: String
    var accessKeyId: String
    var secretAccessKey: String
    var healthPath: String
    var s3Domain: String
    var apiGatewayDomain: String

    /// Only non-sensitive fields are serialized to UserDefaults.
    /// Credentials are stored separately in the Keychain.
    private enum CodingKeys: String, CodingKey {
        case id, name, endpoint, region, healthPath, s3Domain, apiGatewayDomain
    }

    init(
        id: UUID = UUID(),
        name: String = "default connection",
        endpoint: String = "http://localhost:4566",
        region: String = "us-east-1",
        accessKeyId: String = "test",
        secretAccessKey: String = "test",
        healthPath: String = ConnectionProfile.defaultHealthPath,
        s3Domain: String = ConnectionProfile.defaultS3Domain,
        apiGatewayDomain: String = ConnectionProfile.defaultApiGatewayDomain
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.region = region
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.healthPath = healthPath
        self.s3Domain = s3Domain
        self.apiGatewayDomain = apiGatewayDomain
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        region = try container.decode(String.self, forKey: .region)
        healthPath = try container.decodeIfPresent(String.self, forKey: .healthPath) ?? ConnectionProfile.defaultHealthPath
        s3Domain = try container.decodeIfPresent(String.self, forKey: .s3Domain) ?? ConnectionProfile.defaultS3Domain
        apiGatewayDomain = try container.decodeIfPresent(String.self, forKey: .apiGatewayDomain) ?? ConnectionProfile.defaultApiGatewayDomain
        // Credentials are hydrated from Keychain after decoding.
        // Fall back to defaults so profiles without Keychain entries work.
        accessKeyId = KeychainHelper.defaultAccessKeyId
        secretAccessKey = KeychainHelper.defaultSecretAccessKey
    }
}
