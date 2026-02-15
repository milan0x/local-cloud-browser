import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("CloudWatch Logs Models")
struct CloudWatchLogsModelTests {

    // MARK: - CloudWatchLogEvent.isJSON

    @Test("isJSON detects JSON object")
    func isJSONObject() {
        let event = CloudWatchLogEvent(from: ["message": "{\"key\": \"value\"}"])
        #expect(event.isJSON == true)
    }

    @Test("isJSON detects JSON array")
    func isJSONArray() {
        let event = CloudWatchLogEvent(from: ["message": "[1, 2, 3]"])
        #expect(event.isJSON == true)
    }

    @Test("isJSON false for plain text")
    func isJSONPlainText() {
        let event = CloudWatchLogEvent(from: ["message": "just a log line"])
        #expect(event.isJSON == false)
    }

    @Test("isJSON handles whitespace around JSON")
    func isJSONWithWhitespace() {
        let event = CloudWatchLogEvent(from: ["message": "  { \"key\": 1 }  "])
        #expect(event.isJSON == true)
    }

    // MARK: - CloudWatchLogEvent.prettyPrinted

    @Test("prettyPrinted formats valid JSON")
    func prettyPrintedValid() {
        let event = CloudWatchLogEvent(from: ["message": "{\"a\":1}"])
        #expect(event.prettyPrinted != nil)
        #expect(event.prettyPrinted!.contains("\"a\" : 1"))
    }

    @Test("prettyPrinted nil for non-JSON")
    func prettyPrintedNonJSON() {
        let event = CloudWatchLogEvent(from: ["message": "plain text"])
        #expect(event.prettyPrinted == nil)
    }

    // MARK: - CloudWatchLogEvent.displayMessage

    @Test("displayMessage uses prettyPrinted for JSON")
    func displayMessageJSON() {
        let event = CloudWatchLogEvent(from: ["message": "{\"a\":1}"])
        #expect(event.displayMessage.contains("\"a\" : 1"))
    }

    @Test("displayMessage uses raw message for non-JSON")
    func displayMessagePlain() {
        let event = CloudWatchLogEvent(from: ["message": "hello"])
        #expect(event.displayMessage == "hello")
    }

    // MARK: - CloudWatchFilteredLogEvent

    @Test("CloudWatchFilteredLogEvent isJSON and prettyPrinted")
    func filteredEventJSON() {
        let event = CloudWatchFilteredLogEvent(from: [
            "eventId": "e1",
            "logStreamName": "stream1",
            "message": "{\"key\":\"value\"}",
        ])
        #expect(event.isJSON == true)
        #expect(event.prettyPrinted != nil)
    }

    // MARK: - CloudWatchLogGroup.init

    @Test("LogGroup parses from dict")
    func logGroupInit() {
        let group = CloudWatchLogGroup(from: [
            "logGroupName": "/aws/lambda/my-func",
            "arn": "arn:aws:logs:us-east-1:000:log-group:/aws/lambda/my-func",
            "storedBytes": Int64(1048576),
            "retentionInDays": 30,
            "creationTime": 1700000000000.0,
        ])
        #expect(group.logGroupName == "/aws/lambda/my-func")
        #expect(group.retentionInDays == 30)
        #expect(group.storedBytes == 1048576)
        #expect(group.creationTime != nil)
    }

    // MARK: - CLI

    @Test("describeLogGroupsCLI generates valid command")
    func describeLogGroupsCLI() {
        let group = CloudWatchLogGroup(from: ["logGroupName": "/aws/lambda/test"])
        let cli = group.describeLogGroupsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws logs describe-log-groups"))
        #expect(cli.contains("/aws/lambda/test"))
    }

    @Test("describeLogStreamsCLI generates valid command")
    func describeLogStreamsCLI() {
        let group = CloudWatchLogGroup(from: ["logGroupName": "/aws/lambda/test"])
        let cli = group.describeLogStreamsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws logs describe-log-streams"))
    }

    @Test("getLogEventsCLI generates valid command")
    func getLogEventsCLI() {
        let stream = CloudWatchLogStream(from: [
            "logStreamName": "2024/01/15/[$LATEST]abc123",
            "storedBytes": Int64(0),
        ])
        let cli = stream.getLogEventsCLI(logGroupName: "/test", endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws logs get-log-events"))
        #expect(cli.contains("--log-group-name"))
        #expect(cli.contains("--log-stream-name"))
    }
}
