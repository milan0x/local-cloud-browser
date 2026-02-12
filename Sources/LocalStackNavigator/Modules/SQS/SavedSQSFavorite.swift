import Foundation

struct SavedSQSFavorite: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var queueUrl: String
    var messageBody: String
    var delaySeconds: Int?
    var messageGroupId: String?
    var messageDeduplicationId: String?
    var createdAt: Date = Date()

    static let maxNameLength = 25
}
