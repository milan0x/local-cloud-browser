import XCTest
@testable import LocalCloudBrowser

final class SigV4SignerTests: XCTestCase {

    // AWS test vector credentials
    private let testAccessKeyId = "AKIDEXAMPLE"
    private let testSecretAccessKey = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    private let testRegion = "us-east-1"
    private let testService = "service"

    /// Fixed date: 2015-08-30T12:36:00Z (used in AWS SigV4 test suite)
    private var testDate: Date {
        var components = DateComponents()
        components.year = 2015
        components.month = 8
        components.day = 30
        components.hour = 12
        components.minute = 36
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - SHA256

    func testSHA256EmptyBody() {
        let hash = SigV4Signer.hexEncode(SigV4Signer.sha256(Data()))
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSHA256KnownInput() {
        let data = Data("hello".utf8)
        let hash = SigV4Signer.hexEncode(SigV4Signer.sha256(data))
        XCTAssertEqual(hash, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    // MARK: - HMAC-SHA256

    func testHMACSHA256KnownVector() {
        // RFC 4231 Test Case 2
        let key = Data("Jefe".utf8)
        let data = Data("what do ya want for nothing?".utf8)
        let result = SigV4Signer.hexEncode(SigV4Signer.hmacSHA256(key: key, data: data))
        XCTAssertEqual(result, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    // MARK: - Hex encoding

    func testHexEncode() {
        let data = Data([0x00, 0x0f, 0xff, 0xab])
        XCTAssertEqual(SigV4Signer.hexEncode(data), "000fffab")
    }

    // MARK: - URI encoding

    func testURIEncodeSimple() {
        XCTAssertEqual(SigV4Signer.uriEncode("hello", encodeSlash: true), "hello")
    }

    func testURIEncodeSpecialChars() {
        XCTAssertEqual(SigV4Signer.uriEncode("hello world", encodeSlash: true), "hello%20world")
    }

    func testURIEncodeSlashPreserved() {
        XCTAssertEqual(SigV4Signer.uriEncode("/foo/bar", encodeSlash: false), "/foo/bar")
    }

    func testURIEncodeSlashEncoded() {
        XCTAssertEqual(SigV4Signer.uriEncode("/foo/bar", encodeSlash: true), "%2Ffoo%2Fbar")
    }

    // MARK: - Signing key derivation

    func testDeriveSigningKey() {
        let key = SigV4Signer.deriveSigningKey(
            secretAccessKey: testSecretAccessKey,
            date: "20150830",
            region: testRegion,
            service: testService
        )
        // Verified against AWS reference implementation
        XCTAssertEqual(key.count, 32) // SHA256 output
        let hex = SigV4Signer.hexEncode(key)
        XCTAssertEqual(hex, "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9")
    }

    // MARK: - Canonical query string

    func testCanonicalQueryStringEmpty() {
        let url = URL(string: "https://example.amazonaws.com/")!
        XCTAssertEqual(SigV4Signer.canonicalQueryString(from: url), "")
    }

    func testCanonicalQueryStringSorted() {
        let url = URL(string: "https://example.amazonaws.com/?Param2=value2&Param1=value1")!
        XCTAssertEqual(SigV4Signer.canonicalQueryString(from: url), "Param1=value1&Param2=value2")
    }

    // MARK: - Full signing (GET request)

    func testSignGETRequest() {
        var request = URLRequest(url: URL(string: "https://example.amazonaws.com/")!)
        request.httpMethod = "GET"

        SigV4Signer.sign(
            request: &request,
            body: nil,
            region: testRegion,
            service: testService,
            accessKeyId: testAccessKeyId,
            secretAccessKey: testSecretAccessKey,
            date: testDate
        )

        // Verify required headers are set
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-amz-date"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-date"), "20150830T123600Z")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-amz-content-sha256"),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Host"))

        // Authorization header format
        let auth = request.value(forHTTPHeaderField: "Authorization")!
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256"))
        XCTAssertTrue(auth.contains("Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request"))
        XCTAssertTrue(auth.contains("SignedHeaders="))
        XCTAssertTrue(auth.contains("Signature="))
    }

    // MARK: - Full signing (PUT request with body)

    func testSignPUTRequestWithBody() {
        let body = Data("test body content".utf8)
        var request = URLRequest(url: URL(string: "https://example.amazonaws.com/test-object")!)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        SigV4Signer.sign(
            request: &request,
            body: body,
            region: testRegion,
            service: "s3",
            accessKeyId: testAccessKeyId,
            secretAccessKey: testSecretAccessKey,
            date: testDate
        )

        // Body hash should NOT be empty-body hash
        let bodyHash = request.value(forHTTPHeaderField: "x-amz-content-sha256")!
        XCTAssertNotEqual(bodyHash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(bodyHash, SigV4Signer.hexEncode(SigV4Signer.sha256(body)))

        let auth = request.value(forHTTPHeaderField: "Authorization")!
        XCTAssertTrue(auth.contains("Credential=AKIDEXAMPLE/20150830/us-east-1/s3/aws4_request"))
        XCTAssertTrue(auth.contains("Signature="))
    }

    // MARK: - Non-standard port

    func testSignRequestWithNonStandardPort() {
        var request = URLRequest(url: URL(string: "http://localhost:9000/my-bucket")!)
        request.httpMethod = "GET"

        SigV4Signer.sign(
            request: &request,
            body: nil,
            region: "us-east-1",
            service: "s3",
            accessKeyId: "minioadmin",
            secretAccessKey: "minioadmin",
            date: testDate
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "localhost:9000")

        let auth = request.value(forHTTPHeaderField: "Authorization")!
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256"))
        XCTAssertTrue(auth.contains("Signature="))
    }

    // MARK: - Query parameters included in signing

    func testSignRequestWithQueryParams() {
        var request = URLRequest(url: URL(string: "https://s3.amazonaws.com/my-bucket?list-type=2&prefix=docs/")!)
        request.httpMethod = "GET"

        SigV4Signer.sign(
            request: &request,
            body: nil,
            region: testRegion,
            service: "s3",
            accessKeyId: testAccessKeyId,
            secretAccessKey: testSecretAccessKey,
            date: testDate
        )

        let auth = request.value(forHTTPHeaderField: "Authorization")!
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256"))
        // The signature should be deterministic for the same inputs
        let sig1 = auth

        // Sign again with same params — should produce same result
        var request2 = URLRequest(url: URL(string: "https://s3.amazonaws.com/my-bucket?list-type=2&prefix=docs/")!)
        request2.httpMethod = "GET"
        SigV4Signer.sign(
            request: &request2,
            body: nil,
            region: testRegion,
            service: "s3",
            accessKeyId: testAccessKeyId,
            secretAccessKey: testSecretAccessKey,
            date: testDate
        )
        XCTAssertEqual(sig1, request2.value(forHTTPHeaderField: "Authorization"))
    }
}
