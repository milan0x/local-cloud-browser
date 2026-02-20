import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("SQS Models")
struct SQSModelTests {

    // MARK: - SQSQueue

    @Test("queueName extracts name from URL")
    func queueName() {
        let queue = SQSQueue(queueUrl: "http://localhost:4566/000000000000/my-queue")
        #expect(queue.queueName == "my-queue")
    }

    @Test("isFifo detects .fifo suffix")
    func isFifo() {
        let fifo = SQSQueue(queueUrl: "http://localhost:4566/000000000000/my-queue.fifo")
        let standard = SQSQueue(queueUrl: "http://localhost:4566/000000000000/my-queue")
        #expect(fifo.isFifo == true)
        #expect(standard.isFifo == false)
    }

    @Test("queueArn derives ARN from URL")
    func queueArn() {
        let queue = SQSQueue(queueUrl: "http://localhost:4566/000000000000/my-queue")
        let arn = queue.queueArn(region: "us-east-1")
        #expect(arn == "arn:aws:sqs:us-east-1:000000000000:my-queue")
    }

    @Test("queueArn returns nil for invalid URL")
    func queueArnInvalid() {
        let queue = SQSQueue(queueUrl: "not-a-url")
        #expect(queue.queueArn(region: "us-east-1") == nil)
    }

    // MARK: - SQSMessage

    private func makeMessage(body: String, attributes: [String: String] = [:], messageId: String = "test-id") -> SQSMessage {
        SQSMessage(messageId: messageId, receiptHandle: "handle", body: body, md5OfBody: "md5", attributes: attributes)
    }

    @Test("bodyType detects JSON")
    func bodyTypeJSON() {
        #expect(makeMessage(body: "{\"key\": \"value\"}").bodyType == "JSON")
        #expect(makeMessage(body: "[1, 2, 3]").bodyType == "JSON")
    }

    @Test("bodyType detects XML")
    func bodyTypeXML() {
        #expect(makeMessage(body: "<root>hello</root>").bodyType == "XML")
    }

    @Test("bodyType detects plain text")
    func bodyTypeText() {
        #expect(makeMessage(body: "Hello world").bodyType == "Text")
    }

    @Test("bodyType handles whitespace-padded content")
    func bodyTypeWhitespace() {
        #expect(makeMessage(body: "  {\"key\": 1}").bodyType == "JSON")
        #expect(makeMessage(body: "\n<root/>").bodyType == "XML")
    }

    @Test("bodySize returns UTF-8 byte count")
    func bodySize() {
        #expect(makeMessage(body: "hello").bodySize == 5)
        #expect(makeMessage(body: "").bodySize == 0)
    }

    @Test("truncatedId shortens long IDs")
    func truncatedId() {
        let longId = "abcdefgh-1234-5678-9012-ijklmnopqrst"
        let msg = makeMessage(body: "", messageId: longId)
        #expect(msg.truncatedId == "abcdefgh...qrst")
    }

    @Test("truncatedId keeps short IDs intact")
    func truncatedIdShort() {
        let msg = makeMessage(body: "", messageId: "short-id")
        #expect(msg.truncatedId == "short-id")
    }

    @Test("sentTimestamp parses epoch millis")
    func sentTimestamp() {
        let msg = makeMessage(body: "", attributes: ["SentTimestamp": "1705312200000"])
        #expect(msg.sentTimestamp != nil)
    }

    @Test("sentTimestamp returns nil when missing")
    func sentTimestampMissing() {
        let msg = makeMessage(body: "")
        #expect(msg.sentTimestamp == nil)
    }

    @Test("approximateReceiveCount parses from attributes")
    func receiveCount() {
        let msg = makeMessage(body: "", attributes: ["ApproximateReceiveCount": "3"])
        #expect(msg.approximateReceiveCount == 3)
    }

    @Test("approximateReceiveCount defaults to 0")
    func receiveCountDefault() {
        let msg = makeMessage(body: "")
        #expect(msg.approximateReceiveCount == 0)
    }

    @Test("formattedSize formats bytes")
    func formattedSizeBytes() {
        #expect(SQSMessage.formattedSize(500) == "500 B")
    }

    @Test("formattedSize formats kilobytes")
    func formattedSizeKB() {
        let result = SQSMessage.formattedSize(2048)
        #expect(result == "2.0 KB")
    }

    @Test("formattedSize threshold at 1024")
    func formattedSizeThreshold() {
        #expect(SQSMessage.formattedSize(1023) == "1023 B")
        #expect(SQSMessage.formattedSize(1024) == "1.0 KB")
    }

    // MARK: - SQSQueueAttributes

    @Test("Parses attributes from dictionary")
    func parseAttributes() {
        let dict: [String: String] = [
            "ApproximateNumberOfMessages": "5",
            "VisibilityTimeout": "60",
            "QueueArn": "arn:aws:sqs:us-east-1:000:test",
            "FifoQueue": "true",
            "ContentBasedDeduplication": "true",
            "CreatedTimestamp": "1705312200",
        ]
        let attrs = SQSQueueAttributes(from: dict)
        #expect(attrs.approximateNumberOfMessages == 5)
        #expect(attrs.visibilityTimeout == 60)
        #expect(attrs.queueArn == "arn:aws:sqs:us-east-1:000:test")
        #expect(attrs.fifoQueue == true)
        #expect(attrs.contentBasedDeduplication == true)
        #expect(attrs.createdTimestamp != nil)
    }

    @Test("Parses redrive policy from attributes")
    func parseRedrivePolicy() {
        let dict: [String: String] = [
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"arn:aws:sqs:us-east-1:000:dlq\",\"maxReceiveCount\":3}",
        ]
        let attrs = SQSQueueAttributes(from: dict)
        #expect(attrs.redrivePolicy?.deadLetterTargetArn == "arn:aws:sqs:us-east-1:000:dlq")
        #expect(attrs.redrivePolicy?.maxReceiveCount == 3)
    }

    @Test("Defaults for missing attributes")
    func defaultAttributes() {
        let attrs = SQSQueueAttributes(from: [:])
        #expect(attrs.approximateNumberOfMessages == 0)
        #expect(attrs.visibilityTimeout == 30)
        #expect(attrs.maximumMessageSize == 262144)
        #expect(attrs.messageRetentionPeriod == 345600)
        #expect(attrs.fifoQueue == false)
        #expect(attrs.redrivePolicy == nil)
    }

    // MARK: - SQSRedrivePolicy

    @Test("toJSON serializes correctly")
    func redrivePolicyJSON() {
        let policy = SQSRedrivePolicy(deadLetterTargetArn: "arn:dlq", maxReceiveCount: 5)
        let json = policy.toJSON()
        #expect(json.contains("\"deadLetterTargetArn\":\"arn:dlq\""))
        #expect(json.contains("\"maxReceiveCount\":5"))
    }

    // MARK: - CLI Generation

    @Test("sendMessageCLI includes FIFO group ID for FIFO queues")
    func sendMessageCLIFifo() {
        let queue = SQSQueue(queueUrl: "http://localhost:4566/000/test.fifo")
        let cli = queue.sendMessageCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("--message-group-id"))
    }

    @Test("sendMessageCLI excludes group ID for standard queues")
    func sendMessageCLIStandard() {
        let queue = SQSQueue(queueUrl: "http://localhost:4566/000/test")
        let cli = queue.sendMessageCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(!cli.contains("--message-group-id"))
    }

    @Test("toAWSCLI generates valid CLI command")
    func toAWSCLI() {
        let msg = makeMessage(body: "hello world")
        let cli = msg.toAWSCLI(queueUrl: "http://localhost:4566/000/test", endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws sqs send-message"))
        #expect(cli.contains("--message-body"))
        #expect(cli.contains("hello world"))
    }

    @Test("toAWSCLI escapes single quotes in body")
    func toAWSCLIEscapes() {
        let msg = makeMessage(body: "it's a test")
        let cli = msg.toAWSCLI(queueUrl: "http://localhost:4566/000/test", endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("'\\''"))
    }
}
