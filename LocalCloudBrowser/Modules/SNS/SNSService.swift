import Foundation

final class SNSService: BaseService {
    // MARK: - Topic Operations

    func listTopicsPage(token: String? = nil, region: String? = nil) async throws -> ([SNSTopic], String?) {
        var params: [String: String] = [:]
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.snsRequest(action: "ListTopics", params: params, region: region)
        let xml = try SNSXMLParser.parse(data)
        let topics = xml.all("TopicArn").map { SNSTopic(topicArn: $0) }
        return (topics, xml.first("NextToken"))
    }

    func listTopics(region: String? = nil) async throws -> [SNSTopic] {
        var allTopics: [SNSTopic] = []
        var nextToken: String? = nil
        repeat {
            let (topics, token) = try await listTopicsPage(token: nextToken, region: region)
            allTopics.append(contentsOf: topics)
            nextToken = token
            if allTopics.count >= 10_000 { break }
        } while nextToken != nil
        return allTopics
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
            throw CloudClientError.invalidURL
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

    func listSubscriptionsPage(topicArn: String, token: String? = nil) async throws -> ([SNSSubscription], String?) {
        var params: [String: String] = ["TopicArn": topicArn]
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.snsRequest(action: "ListSubscriptionsByTopic", params: params)
        let xml = try SNSXMLParser.parse(data)
        var subs: [SNSSubscription] = []
        for member in xml.memberDicts {
            guard let subArn = member["SubscriptionArn"],
                  let topicArn = member["TopicArn"],
                  let proto = member["Protocol"],
                  let endpoint = member["Endpoint"] else {
                continue
            }
            subs.append(SNSSubscription(
                subscriptionArn: subArn,
                topicArn: topicArn,
                protocol_: proto,
                endpoint: endpoint,
                owner: member["Owner"] ?? ""
            ))
        }
        return (subs, xml.first("NextToken"))
    }

    func listSubscriptions(topicArn: String) async throws -> [SNSSubscription] {
        var allSubs: [SNSSubscription] = []
        var nextToken: String? = nil
        repeat {
            let (subs, token) = try await listSubscriptionsPage(topicArn: topicArn, token: nextToken)
            allSubs.append(contentsOf: subs)
            nextToken = token
            if allSubs.count >= 10_000 { break }
        } while nextToken != nil
        return allSubs
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
            throw CloudClientError.invalidURL
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
            throw CloudClientError.invalidURL
        }
        return messageId
    }
}
