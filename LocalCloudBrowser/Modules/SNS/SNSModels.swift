import Foundation

struct SNSTopic: Identifiable, Hashable {
    let topicArn: String

    var id: String { topicArn }

    var topicName: String {
        topicArn.components(separatedBy: ":").last ?? topicArn
    }

    var isFifo: Bool {
        topicName.hasSuffix(".fifo")
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func publishCLI(endpointUrl: String, region: String) -> String {
        var lines = [
            "aws sns publish \\",
            "  --topic-arn \(topicArn) \\",
            "  --message '<message body>' \\"
        ]
        if isFifo {
            lines.append("  --message-group-id '<group-id>' \\")
        }
        lines.append("  --endpoint-url '\(endpointUrl)' \\")
        lines.append("  --region '\(region)'")
        return lines.joined(separator: "\n")
    }

    func listSubscriptionsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws sns list-subscriptions-by-topic \\",
            "  --topic-arn \(topicArn) \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }

    func getAttributesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws sns get-topic-attributes \\",
            "  --topic-arn \(topicArn) \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }
}

struct SNSSubscription: Identifiable, Hashable {
    let subscriptionArn: String
    let topicArn: String
    let protocol_: String
    let endpoint: String
    let owner: String

    var id: String { subscriptionArn }

    var isPending: Bool {
        subscriptionArn == "PendingConfirmation"
    }

    var truncatedArn: String {
        if subscriptionArn.count <= 20 {
            return subscriptionArn
        }
        return String(subscriptionArn.prefix(12)) + "..." + String(subscriptionArn.suffix(6))
    }

    func getAttributesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws sns get-subscription-attributes \\",
            "  --subscription-arn \(subscriptionArn) \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }

    var truncatedEndpoint: String {
        if endpoint.count <= 50 {
            return endpoint
        }
        return String(endpoint.prefix(30)) + "..." + String(endpoint.suffix(15))
    }
}

struct SNSSubscriptionAttributes {
    var subscriptionArn: String
    var topicArn: String
    var protocol_: String
    var endpoint: String
    var owner: String
    var confirmationWasAuthenticated: Bool
    var pendingConfirmation: Bool
    var rawMessageDelivery: Bool
    var filterPolicy: String?
    var filterPolicyScope: String?
    var deliveryPolicy: String?
    var effectiveDeliveryPolicy: String?
    var redrivePolicy: String?

    init(from dict: [String: String]) {
        subscriptionArn = dict["SubscriptionArn"] ?? ""
        topicArn = dict["TopicArn"] ?? ""
        protocol_ = dict["Protocol"] ?? ""
        endpoint = dict["Endpoint"] ?? ""
        owner = dict["Owner"] ?? ""
        confirmationWasAuthenticated = dict["ConfirmationWasAuthenticated"] == "true"
        pendingConfirmation = dict["PendingConfirmation"] == "true"
        rawMessageDelivery = dict["RawMessageDelivery"] == "true"
        filterPolicy = dict["FilterPolicy"]
        filterPolicyScope = dict["FilterPolicyScope"]
        deliveryPolicy = dict["DeliveryPolicy"]
        effectiveDeliveryPolicy = dict["EffectiveDeliveryPolicy"]
        redrivePolicy = dict["RedrivePolicy"]
    }
}

struct SNSTopicAttributes {
    var displayName: String
    var topicArn: String
    var owner: String
    var subscriptionsConfirmed: Int
    var subscriptionsPending: Int
    var subscriptionsDeleted: Int
    var effectiveDeliveryPolicy: String?
    var policy: String?
    var fifoTopic: Bool
    var contentBasedDeduplication: Bool

    init(from dict: [String: String]) {
        displayName = dict["DisplayName"] ?? ""
        topicArn = dict["TopicArn"] ?? ""
        owner = dict["Owner"] ?? ""
        subscriptionsConfirmed = Int(dict["SubscriptionsConfirmed"] ?? "") ?? 0
        subscriptionsPending = Int(dict["SubscriptionsPending"] ?? "") ?? 0
        subscriptionsDeleted = Int(dict["SubscriptionsDeleted"] ?? "") ?? 0
        effectiveDeliveryPolicy = dict["EffectiveDeliveryPolicy"]
        policy = dict["Policy"]
        fifoTopic = dict["FifoTopic"] == "true"
        contentBasedDeduplication = dict["ContentBasedDeduplication"] == "true"
    }
}
