import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("ServiceError")
struct ServiceErrorTests {

    // MARK: - XML Parsing

    @Test("Parses XML error response")
    func parseXML() {
        let xml = """
            <ErrorResponse><Error>\
            <Code>BucketNotEmpty</Code>\
            <Message>The bucket you tried to delete is not empty</Message>\
            </Error></ErrorResponse>
            """
        let error = ServiceError.parse(from: Data(xml.utf8))
        #expect(error?.code == "BucketNotEmpty")
        #expect(error?.message == "The bucket you tried to delete is not empty")
    }

    @Test("Parses minimal XML error")
    func parseMinimalXML() {
        let xml = "<Error><Code>NoSuchKey</Code><Message>Key not found</Message></Error>"
        let error = ServiceError.parse(from: Data(xml.utf8))
        #expect(error?.code == "NoSuchKey")
        #expect(error?.message == "Key not found")
    }

    // MARK: - JSON Parsing

    @Test("Parses JSON error with __type hash format")
    func parseJSONHash() {
        let json = """
            {"__type": "com.amazonaws.sqs#QueueDoesNotExist", "message": "Queue not found"}
            """
        let error = ServiceError.parse(from: Data(json.utf8))
        #expect(error?.code == "QueueDoesNotExist")
        #expect(error?.message == "Queue not found")
    }

    @Test("Parses JSON error with simple __type")
    func parseJSONSimpleType() {
        let json = """
            {"__type": "NotFound", "message": "Resource not found"}
            """
        let error = ServiceError.parse(from: Data(json.utf8))
        #expect(error?.code == "NotFound")
        #expect(error?.message == "Resource not found")
    }

    @Test("Parses JSON error with capital Message")
    func parseJSONCapitalMessage() {
        let json = """
            {"__type": "AccessDenied", "Message": "Access denied"}
            """
        let error = ServiceError.parse(from: Data(json.utf8))
        #expect(error?.code == "AccessDenied")
        #expect(error?.message == "Access denied")
    }

    @Test("Returns nil for non-error data")
    func parseGarbage() {
        let error = ServiceError.parse(from: Data("not an error".utf8))
        #expect(error == nil)
    }

    @Test("Returns nil for empty data")
    func parseEmpty() {
        let error = ServiceError.parse(from: Data())
        #expect(error == nil)
    }

    @Test("Returns nil for JSON without __type")
    func parseMissingType() {
        let json = """
            {"error": "something", "message": "oops"}
            """
        let error = ServiceError.parse(from: Data(json.utf8))
        #expect(error == nil)
    }

    // MARK: - Friendly Messages

    @Test("BucketNotEmpty has friendly message")
    func friendlyBucketNotEmpty() {
        let error = ServiceError(code: "BucketNotEmpty", message: "raw")
        #expect(error.friendlyMessage.contains("not empty"))
    }

    @Test("BucketAlreadyExists has friendly message")
    func friendlyBucketAlreadyExists() {
        let error = ServiceError(code: "BucketAlreadyExists", message: "raw")
        #expect(error.friendlyMessage.contains("already exists"))
    }

    @Test("Unknown code falls back to raw message")
    func friendlyUnknown() {
        let error = ServiceError(code: "SomeUnknownCode", message: "the raw message")
        #expect(error.friendlyMessage == "the raw message")
    }

    @Test("QueueDoesNotExist has friendly message")
    func friendlyQueueDoesNotExist() {
        let error = ServiceError(code: "QueueDoesNotExist", message: "raw")
        #expect(error.friendlyMessage.contains("no longer exists"))
    }

    @Test("AccessDenied has friendly message")
    func friendlyAccessDenied() {
        let error = ServiceError(code: "AccessDenied", message: "raw")
        #expect(error.friendlyMessage.contains("Access denied"))
    }
}
