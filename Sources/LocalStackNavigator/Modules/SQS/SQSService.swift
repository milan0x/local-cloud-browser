import Foundation

@MainActor
final class SQSService: ObservableObject {
    private var client: LocalStackClient

    init(client: LocalStackClient) {
        self.client = client
    }

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Queue Operations

    func listQueues() async throws -> [SQSQueue] {
        let data = try await client.sqsRequest(action: "ListQueues")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urls = json["QueueUrls"] as? [String] else {
            return []
        }
        return urls.map { SQSQueue(queueUrl: $0) }
    }

    func getQueueAttributes(queueUrl: String, attributeNames: [String] = ["All"]) async throws -> [String: String] {
        let payload: [String: Any] = [
            "QueueUrl": queueUrl,
            "AttributeNames": attributeNames,
        ]
        let data = try await client.sqsRequest(action: "GetQueueAttributes", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let attrs = json["Attributes"] as? [String: String] else {
            return [:]
        }
        return attrs
    }

    func createQueue(name: String, isFifo: Bool) async throws -> String {
        var attributes: [String: String] = [:]
        if isFifo {
            attributes["FifoQueue"] = "true"
            attributes["ContentBasedDeduplication"] = "true"
        }
        var payload: [String: Any] = ["QueueName": name]
        if !attributes.isEmpty {
            payload["Attributes"] = attributes
        }
        let data = try await client.sqsRequest(action: "CreateQueue", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["QueueUrl"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return url
    }

    func deleteQueue(queueUrl: String) async throws {
        _ = try await client.sqsRequest(action: "DeleteQueue", payload: ["QueueUrl": queueUrl])
    }

    func purgeQueue(queueUrl: String) async throws {
        _ = try await client.sqsRequest(action: "PurgeQueue", payload: ["QueueUrl": queueUrl])
    }

    // MARK: - Message Operations

    func sendMessage(
        queueUrl: String,
        body: String,
        delaySeconds: Int? = nil,
        messageGroupId: String? = nil,
        messageDeduplicationId: String? = nil
    ) async throws -> String {
        var payload: [String: Any] = [
            "QueueUrl": queueUrl,
            "MessageBody": body,
        ]
        if let delaySeconds, delaySeconds > 0 {
            payload["DelaySeconds"] = delaySeconds
        }
        if let messageGroupId, !messageGroupId.isEmpty {
            payload["MessageGroupId"] = messageGroupId
        }
        if let messageDeduplicationId, !messageDeduplicationId.isEmpty {
            payload["MessageDeduplicationId"] = messageDeduplicationId
        }
        let data = try await client.sqsRequest(action: "SendMessage", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageId = json["MessageId"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return messageId
    }

    func receiveMessages(queueUrl: String, maxMessages: Int = 10, visibilityTimeout: Int = 0) async throws -> [SQSMessage] {
        let payload: [String: Any] = [
            "QueueUrl": queueUrl,
            "MaxNumberOfMessages": min(maxMessages, 10),
            "VisibilityTimeout": visibilityTimeout,
            "AttributeNames": ["All"],
        ]
        let data = try await client.sqsRequest(action: "ReceiveMessage", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["Messages"] as? [[String: Any]] else {
            return []
        }
        return messages.compactMap { msg in
            guard let messageId = msg["MessageId"] as? String,
                  let receiptHandle = msg["ReceiptHandle"] as? String,
                  let body = msg["Body"] as? String,
                  let md5 = msg["MD5OfBody"] as? String else {
                return nil
            }
            let attrs = msg["Attributes"] as? [String: String] ?? [:]
            return SQSMessage(
                messageId: messageId,
                receiptHandle: receiptHandle,
                body: body,
                md5OfBody: md5,
                attributes: attrs
            )
        }
    }

    func deleteMessage(queueUrl: String, receiptHandle: String) async throws {
        _ = try await client.sqsRequest(action: "DeleteMessage", payload: [
            "QueueUrl": queueUrl,
            "ReceiptHandle": receiptHandle,
        ])
    }

    // MARK: - Attribute Operations

    func setQueueAttributes(queueUrl: String, attributes: [String: String]) async throws {
        _ = try await client.sqsRequest(action: "SetQueueAttributes", payload: [
            "QueueUrl": queueUrl,
            "Attributes": attributes,
        ])
    }
}
