import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("SNS Models")
struct SNSModelTests {

    // MARK: - SNSTopic

    @Test("topicName extracts from ARN")
    func topicName() {
        let topic = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000000000000:my-topic")
        #expect(topic.topicName == "my-topic")
    }

    @Test("isFifo detects .fifo suffix")
    func isFifo() {
        let fifo = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:my-topic.fifo")
        let standard = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:my-topic")
        #expect(fifo.isFifo == true)
        #expect(standard.isFifo == false)
    }

    @Test("publishCLI includes group ID for FIFO topics")
    func publishCLIFifo() {
        let topic = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:topic.fifo")
        let cli = topic.publishCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("--message-group-id"))
    }

    @Test("publishCLI excludes group ID for standard topics")
    func publishCLIStandard() {
        let topic = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:topic")
        let cli = topic.publishCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(!cli.contains("--message-group-id"))
    }

    @Test("listSubscriptionsCLI generates valid command")
    func listSubscriptionsCLI() {
        let topic = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:topic")
        let cli = topic.listSubscriptionsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws sns list-subscriptions-by-topic"))
        #expect(cli.contains("--topic-arn"))
    }

    @Test("getAttributesCLI generates valid command")
    func getAttributesCLI() {
        let topic = SNSTopic(topicArn: "arn:aws:sns:us-east-1:000:topic")
        let cli = topic.getAttributesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws sns get-topic-attributes"))
    }

    // MARK: - SNSSubscription

    @Test("isPending detects PendingConfirmation")
    func isPending() {
        let pending = SNSSubscription(subscriptionArn: "PendingConfirmation", topicArn: "arn:topic", protocol_: "email", endpoint: "a@b.com", owner: "000")
        let confirmed = SNSSubscription(subscriptionArn: "arn:aws:sns:us-east-1:000:topic:uuid", topicArn: "arn:topic", protocol_: "email", endpoint: "a@b.com", owner: "000")
        #expect(pending.isPending == true)
        #expect(confirmed.isPending == false)
    }

    @Test("isPending detects PendingConfirmation in ARN-style subscription ARN")
    func isPendingARN() {
        let pending = SNSSubscription(subscriptionArn: "arn:aws:sns:us-east-1:000:topic:PendingConfirmation", topicArn: "arn:topic", protocol_: "email", endpoint: "a@b.com", owner: "000")
        #expect(pending.isPending == true)
    }

    @Test("truncatedArn shortens long ARNs")
    func truncatedArn() {
        let sub = SNSSubscription(subscriptionArn: "arn:aws:sns:us-east-1:000000000000:my-topic:abc123-def456-ghi789", topicArn: "", protocol_: "", endpoint: "", owner: "")
        #expect(sub.truncatedArn.contains("..."))
        #expect(sub.truncatedArn.count < sub.subscriptionArn.count)
    }

    @Test("truncatedArn keeps short ARNs intact")
    func truncatedArnShort() {
        let sub = SNSSubscription(subscriptionArn: "PendingConfirmation", topicArn: "", protocol_: "", endpoint: "", owner: "")
        #expect(sub.truncatedArn == "PendingConfirmation")
    }

    @Test("truncatedEndpoint shortens long endpoints")
    func truncatedEndpoint() {
        let longEndpoint = "arn:aws:sqs:us-east-1:000000000000:my-very-long-queue-name-that-exceeds-limit"
        let sub = SNSSubscription(subscriptionArn: "arn", topicArn: "", protocol_: "", endpoint: longEndpoint, owner: "")
        #expect(sub.truncatedEndpoint.contains("..."))
    }

    @Test("truncatedEndpoint keeps short endpoints intact")
    func truncatedEndpointShort() {
        let sub = SNSSubscription(subscriptionArn: "arn", topicArn: "", protocol_: "", endpoint: "a@b.com", owner: "")
        #expect(sub.truncatedEndpoint == "a@b.com")
    }

    @Test("getAttributesCLI generates valid command")
    func subGetAttributesCLI() {
        let sub = SNSSubscription(subscriptionArn: "arn:sub:1", topicArn: "arn:topic", protocol_: "sqs", endpoint: "arn:queue", owner: "000")
        let cli = sub.getAttributesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws sns get-subscription-attributes"))
        #expect(cli.contains("--subscription-arn"))
    }

    // MARK: - SNSSubscriptionAttributes

    @Test("Parses subscription attributes from dict")
    func parseSubscriptionAttributes() {
        let dict: [String: String] = [
            "SubscriptionArn": "arn:sub:1",
            "TopicArn": "arn:topic:1",
            "Protocol": "email",
            "Endpoint": "user@example.com",
            "Owner": "000",
            "ConfirmationWasAuthenticated": "true",
            "PendingConfirmation": "false",
            "RawMessageDelivery": "true",
            "FilterPolicy": "{\"key\": [\"value\"]}",
        ]
        let attrs = SNSSubscriptionAttributes(from: dict)
        #expect(attrs.subscriptionArn == "arn:sub:1")
        #expect(attrs.protocol_ == "email")
        #expect(attrs.confirmationWasAuthenticated == true)
        #expect(attrs.pendingConfirmation == false)
        #expect(attrs.rawMessageDelivery == true)
        #expect(attrs.filterPolicy != nil)
    }

    @Test("Defaults for missing subscription attributes")
    func defaultSubscriptionAttributes() {
        let attrs = SNSSubscriptionAttributes(from: [:])
        #expect(attrs.subscriptionArn == "")
        #expect(attrs.confirmationWasAuthenticated == false)
        #expect(attrs.pendingConfirmation == false)
        #expect(attrs.rawMessageDelivery == false)
        #expect(attrs.filterPolicy == nil)
    }

    // MARK: - SNSTopicAttributes

    @Test("Parses topic attributes from dict")
    func parseTopicAttributes() {
        let dict: [String: String] = [
            "DisplayName": "My Topic",
            "TopicArn": "arn:topic",
            "Owner": "000",
            "SubscriptionsConfirmed": "3",
            "SubscriptionsPending": "1",
            "SubscriptionsDeleted": "0",
            "FifoTopic": "true",
            "ContentBasedDeduplication": "true",
        ]
        let attrs = SNSTopicAttributes(from: dict)
        #expect(attrs.displayName == "My Topic")
        #expect(attrs.subscriptionsConfirmed == 3)
        #expect(attrs.subscriptionsPending == 1)
        #expect(attrs.subscriptionsDeleted == 0)
        #expect(attrs.fifoTopic == true)
        #expect(attrs.contentBasedDeduplication == true)
    }

    @Test("Defaults for missing topic attributes")
    func defaultTopicAttributes() {
        let attrs = SNSTopicAttributes(from: [:])
        #expect(attrs.displayName == "")
        #expect(attrs.subscriptionsConfirmed == 0)
        #expect(attrs.fifoTopic == false)
        #expect(attrs.contentBasedDeduplication == false)
    }
}
