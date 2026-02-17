import Foundation

final class SNSService: LocalStackService {
    // MARK: - Topic Operations

    func listTopics(region: String? = nil) async throws -> [SNSTopic] {
        var topics: [SNSTopic] = []
        var nextToken: String? = nil

        repeat {
            var params: [String: String] = [:]
            if let token = nextToken {
                params["NextToken"] = token
            }
            let data = try await client.snsRequest(action: "ListTopics", params: params, region: region)
            let xml = try SNSXMLParser.parse(data)
            let arns = xml.all("TopicArn")
            for arn in arns {
                topics.append(SNSTopic(topicArn: arn))
            }
            nextToken = xml.first("NextToken")
        } while nextToken != nil

        return topics
    }

    func createTopic(name: String, isFifo: Bool) async throws -> String {
        var params: [String: String] = ["Name": name]
        if isFifo {
            params["Attributes.entry.1.key"] = "FifoTopic"
            params["Attributes.entry.1.value"] = "true"
            params["Attributes.entry.2.key"] = "ContentBasedDeduplication"
            params["Attributes.entry.2.value"] = "true"
        }
        let data = try await client.snsRequest(action: "CreateTopic", params: params)
        let xml = try SNSXMLParser.parse(data)
        guard let arn = xml.first("TopicArn") else {
            throw LocalStackClientError.invalidURL
        }
        return arn
    }

    func deleteTopic(topicArn: String) async throws {
        _ = try await client.snsRequest(action: "DeleteTopic", params: ["TopicArn": topicArn])
    }

    func getTopicAttributes(topicArn: String) async throws -> [String: String] {
        let data = try await client.snsRequest(action: "GetTopicAttributes", params: ["TopicArn": topicArn])
        let xml = try SNSXMLParser.parse(data)
        return xml.attributeDict
    }

    // MARK: - Subscription Operations

    func listSubscriptions(topicArn: String) async throws -> [SNSSubscription] {
        var subscriptions: [SNSSubscription] = []
        var nextToken: String? = nil

        repeat {
            var params: [String: String] = ["TopicArn": topicArn]
            if let token = nextToken {
                params["NextToken"] = token
            }
            let data = try await client.snsRequest(action: "ListSubscriptionsByTopic", params: params)
            let xml = try SNSXMLParser.parse(data)
            for member in xml.memberDicts {
                guard let subArn = member["SubscriptionArn"],
                      let topicArn = member["TopicArn"],
                      let proto = member["Protocol"],
                      let endpoint = member["Endpoint"] else {
                    continue
                }
                subscriptions.append(SNSSubscription(
                    subscriptionArn: subArn,
                    topicArn: topicArn,
                    protocol_: proto,
                    endpoint: endpoint,
                    owner: member["Owner"] ?? ""
                ))
            }
            nextToken = xml.first("NextToken")
        } while nextToken != nil

        return subscriptions
    }

    func subscribe(topicArn: String, protocol_: String, endpoint: String) async throws -> String {
        let params: [String: String] = [
            "TopicArn": topicArn,
            "Protocol": protocol_,
            "Endpoint": endpoint,
        ]
        let data = try await client.snsRequest(action: "Subscribe", params: params)
        let xml = try SNSXMLParser.parse(data)
        guard let subArn = xml.first("SubscriptionArn") else {
            throw LocalStackClientError.invalidURL
        }
        return subArn
    }

    func getSubscriptionAttributes(subscriptionArn: String) async throws -> [String: String] {
        let data = try await client.snsRequest(action: "GetSubscriptionAttributes", params: [
            "SubscriptionArn": subscriptionArn,
        ])
        let xml = try SNSXMLParser.parse(data)
        return xml.attributeDict
    }

    func unsubscribe(subscriptionArn: String) async throws {
        _ = try await client.snsRequest(action: "Unsubscribe", params: [
            "SubscriptionArn": subscriptionArn,
        ])
    }

    // MARK: - Publish

    func publish(
        topicArn: String,
        message: String,
        subject: String? = nil,
        messageGroupId: String? = nil,
        messageDeduplicationId: String? = nil
    ) async throws -> String {
        var params: [String: String] = [
            "TopicArn": topicArn,
            "Message": message,
        ]
        if let subject, !subject.isEmpty {
            params["Subject"] = subject
        }
        if let messageGroupId, !messageGroupId.isEmpty {
            params["MessageGroupId"] = messageGroupId
        }
        if let messageDeduplicationId, !messageDeduplicationId.isEmpty {
            params["MessageDeduplicationId"] = messageDeduplicationId
        }
        let data = try await client.snsRequest(action: "Publish", params: params)
        let xml = try SNSXMLParser.parse(data)
        guard let messageId = xml.first("MessageId") else {
            throw LocalStackClientError.invalidURL
        }
        return messageId
    }
}
