import Foundation

struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var endpoint: String
    var region: String
    var accessKeyId: String
    var secretAccessKey: String

    init(
        id: UUID = UUID(),
        name: String = "Default",
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
}
