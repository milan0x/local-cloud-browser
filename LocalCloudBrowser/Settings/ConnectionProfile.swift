import Foundation

enum EndpointType: String, Codable, Sendable {
    case localstack
    case minio
    case generic
}

struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    static let defaultHealthPath = ""
    static let defaultS3Domain = ""
    static let defaultApiGatewayDomain = ""

    var id: UUID
    var name: String
    var endpoint: String
    var region: String
    var accessKeyId: String
    var secretAccessKey: String
    var healthPath: String
    var s3Domain: String
    var apiGatewayDomain: String
    var endpointType: EndpointType

    /// Only non-sensitive fields are serialized to UserDefaults.
    /// Credentials are stored separately in the Keychain.
    private enum CodingKeys: String, CodingKey {
        case id, name, endpoint, region, healthPath, s3Domain, apiGatewayDomain, endpointType
    }

    init(
        id: UUID = UUID(),
        name: String = "My Connection",
        endpoint: String = "http://localhost:4566",
        region: String = "us-east-1",
        accessKeyId: String = "test",
        secretAccessKey: String = "test",
        healthPath: String = ConnectionProfile.defaultHealthPath,
        s3Domain: String = ConnectionProfile.defaultS3Domain,
        apiGatewayDomain: String = ConnectionProfile.defaultApiGatewayDomain,
        endpointType: EndpointType = .generic
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
        self.endpointType = endpointType
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
        endpointType = try container.decodeIfPresent(EndpointType.self, forKey: .endpointType) ?? .generic
        // Credentials are hydrated from Keychain after decoding.
        // Fall back to defaults so profiles without Keychain entries work.
        accessKeyId = KeychainHelper.defaultAccessKeyId
        secretAccessKey = KeychainHelper.defaultSecretAccessKey
    }
}
