import Foundation

struct ConnectionSettings: Codable, Sendable {
    var endpoint: String = "http://localhost:4566"
    var region: String = "us-east-1"
    var accessKeyId: String = "test"
    var secretAccessKey: String = "test"
}
