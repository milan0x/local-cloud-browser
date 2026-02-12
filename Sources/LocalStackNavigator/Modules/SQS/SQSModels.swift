import Foundation

struct SQSQueue: Identifiable, Hashable {
    let queueUrl: String

    var id: String { queueUrl }

    var queueName: String {
        queueUrl.components(separatedBy: "/").last ?? queueUrl
    }

    var isFifo: Bool {
        queueName.hasSuffix(".fifo")
    }
}

struct SQSQueueAttributes {
    var approximateNumberOfMessages: Int = 0
    var approximateNumberOfMessagesNotVisible: Int = 0
    var approximateNumberOfMessagesDelayed: Int = 0
    var visibilityTimeout: Int = 30
    var delaySeconds: Int = 0
    var maximumMessageSize: Int = 262144
    var messageRetentionPeriod: Int = 345600
    var receiveMessageWaitTimeSeconds: Int = 0
    var createdTimestamp: Date?
    var lastModifiedTimestamp: Date?
    var queueArn: String = ""
    var fifoQueue: Bool = false
    var contentBasedDeduplication: Bool = false
    var redrivePolicy: SQSRedrivePolicy?

    init(from dict: [String: String]) {
        approximateNumberOfMessages = Int(dict["ApproximateNumberOfMessages"] ?? "") ?? 0
        approximateNumberOfMessagesNotVisible = Int(dict["ApproximateNumberOfMessagesNotVisible"] ?? "") ?? 0
        approximateNumberOfMessagesDelayed = Int(dict["ApproximateNumberOfMessagesDelayed"] ?? "") ?? 0
        visibilityTimeout = Int(dict["VisibilityTimeout"] ?? "") ?? 30
        delaySeconds = Int(dict["DelaySeconds"] ?? "") ?? 0
        maximumMessageSize = Int(dict["MaximumMessageSize"] ?? "") ?? 262144
        messageRetentionPeriod = Int(dict["MessageRetentionPeriod"] ?? "") ?? 345600
        receiveMessageWaitTimeSeconds = Int(dict["ReceiveMessageWaitTimeSeconds"] ?? "") ?? 0
        queueArn = dict["QueueArn"] ?? ""
        fifoQueue = dict["FifoQueue"] == "true"
        contentBasedDeduplication = dict["ContentBasedDeduplication"] == "true"

        if let ts = Double(dict["CreatedTimestamp"] ?? "") {
            createdTimestamp = Date(timeIntervalSince1970: ts)
        }
        if let ts = Double(dict["LastModifiedTimestamp"] ?? "") {
            lastModifiedTimestamp = Date(timeIntervalSince1970: ts)
        }

        if let redrivePolicyJSON = dict["RedrivePolicy"],
           let data = redrivePolicyJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let deadLetterTargetArn = json["deadLetterTargetArn"] as? String ?? ""
            let maxReceiveCount = json["maxReceiveCount"] as? Int
                ?? Int(json["maxReceiveCount"] as? String ?? "") ?? 5
            redrivePolicy = SQSRedrivePolicy(
                deadLetterTargetArn: deadLetterTargetArn,
                maxReceiveCount: maxReceiveCount
            )
        }
    }
}

struct SQSRedrivePolicy {
    var deadLetterTargetArn: String
    var maxReceiveCount: Int

    func toJSON() -> String {
        "{\"deadLetterTargetArn\":\"\(deadLetterTargetArn)\",\"maxReceiveCount\":\(maxReceiveCount)}"
    }
}

struct SQSMessage: Identifiable, Hashable {
    let messageId: String
    let receiptHandle: String
    let body: String
    let md5OfBody: String
    let attributes: [String: String]

    var id: String { messageId }

    var sentTimestamp: Date? {
        guard let ts = attributes["SentTimestamp"], let ms = Double(ts) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    var approximateReceiveCount: Int {
        Int(attributes["ApproximateReceiveCount"] ?? "") ?? 0
    }

    var firstReceiveTimestamp: Date? {
        guard let ts = attributes["ApproximateFirstReceiveTimestamp"], let ms = Double(ts), ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    var senderId: String? {
        attributes["SenderId"]
    }

    var messageGroupId: String? {
        attributes["MessageGroupId"]
    }

    var bodyType: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "JSON"
        } else if trimmed.hasPrefix("<") {
            return "XML"
        }
        return "Text"
    }

    var bodySize: Int {
        body.utf8.count
    }

    /// Non-optional epoch millis for stable sorting (0 if no timestamp)
    var sentTimestampMillis: Double {
        Double(attributes["SentTimestamp"] ?? "") ?? 0
    }

    var truncatedId: String {
        if messageId.count <= 16 {
            return messageId
        }
        return String(messageId.prefix(8)) + "..." + String(messageId.suffix(4))
    }

    static func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        }
    }
}
