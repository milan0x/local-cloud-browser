import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("SNSXMLParser")
struct SNSXMLParserTests {

    @Test("Parses leaf text values")
    func leafValues() throws {
        let xml = """
            <ListTopicsResponse>
                <ListTopicsResult>
                    <Topics>
                        <member><TopicArn>arn:aws:sns:us-east-1:000000000000:my-topic</TopicArn></member>
                        <member><TopicArn>arn:aws:sns:us-east-1:000000000000:other-topic</TopicArn></member>
                    </Topics>
                </ListTopicsResult>
            </ListTopicsResponse>
            """
        let parsed = try SNSXMLParser.parse(Data(xml.utf8))
        let arns = parsed.all("TopicArn")
        #expect(arns.count == 2)
        #expect(arns[0] == "arn:aws:sns:us-east-1:000000000000:my-topic")
        #expect(arns[1] == "arn:aws:sns:us-east-1:000000000000:other-topic")
    }

    @Test("first() returns first matching element")
    func first() throws {
        let xml = """
            <Response><RequestId>abc-123</RequestId><TopicArn>arn:first</TopicArn><TopicArn>arn:second</TopicArn></Response>
            """
        let parsed = try SNSXMLParser.parse(Data(xml.utf8))
        #expect(parsed.first("RequestId") == "abc-123")
        #expect(parsed.first("TopicArn") == "arn:first")
        #expect(parsed.first("NonExistent") == nil)
    }

    @Test("Parses member groups into dicts")
    func memberGroups() throws {
        let xml = """
            <ListSubscriptionsResponse>
                <ListSubscriptionsResult>
                    <Subscriptions>
                        <member>
                            <SubscriptionArn>arn:sub:1</SubscriptionArn>
                            <Protocol>email</Protocol>
                            <Endpoint>user@example.com</Endpoint>
                        </member>
                        <member>
                            <SubscriptionArn>arn:sub:2</SubscriptionArn>
                            <Protocol>sqs</Protocol>
                            <Endpoint>arn:aws:sqs:us-east-1:000:queue</Endpoint>
                        </member>
                    </Subscriptions>
                </ListSubscriptionsResult>
            </ListSubscriptionsResponse>
            """
        let parsed = try SNSXMLParser.parse(Data(xml.utf8))
        #expect(parsed.memberDicts.count == 2)
        #expect(parsed.memberDicts[0]["Protocol"] == "email")
        #expect(parsed.memberDicts[0]["Endpoint"] == "user@example.com")
        #expect(parsed.memberDicts[1]["Protocol"] == "sqs")
    }

    @Test("Parses attribute entries")
    func attributeEntries() throws {
        let xml = """
            <GetTopicAttributesResponse>
                <GetTopicAttributesResult>
                    <Attributes>
                        <entry><key>TopicArn</key><value>arn:topic</value></entry>
                        <entry><key>DisplayName</key><value>My Topic</value></entry>
                    </Attributes>
                </GetTopicAttributesResult>
            </GetTopicAttributesResponse>
            """
        let parsed = try SNSXMLParser.parse(Data(xml.utf8))
        #expect(parsed.attributeDict["TopicArn"] == "arn:topic")
        #expect(parsed.attributeDict["DisplayName"] == "My Topic")
    }

    @Test("Throws on invalid XML")
    func invalidXML() {
        let bad = Data("<<<not xml>>>".utf8)
        #expect(throws: SNSXMLParseError.self) {
            _ = try SNSXMLParser.parse(bad)
        }
    }

    @Test("Parses empty response")
    func emptyResponse() throws {
        let xml = "<Response></Response>"
        let parsed = try SNSXMLParser.parse(Data(xml.utf8))
        #expect(parsed.leafValues.isEmpty)
        #expect(parsed.memberDicts.isEmpty)
        #expect(parsed.attributeDict.isEmpty)
    }
}
