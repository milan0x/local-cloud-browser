import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("SSM Models")
struct SSMModelTests {

    // MARK: - SSMParameter

    @Test("displayType returns type")
    func displayType() {
        let param = SSMParameter(from: ["Name": "/app/key", "Type": "SecureString"])
        #expect(param.displayType == "SecureString")
    }

    @Test("isSecureString detects SecureString type")
    func isSecureString() {
        let secure = SSMParameter(from: ["Name": "/key", "Type": "SecureString"])
        let plain = SSMParameter(from: ["Name": "/key", "Type": "String"])
        #expect(secure.isSecureString == true)
        #expect(plain.isSecureString == false)
    }

    @Test("Parses parameter from dictionary")
    func parseParameter() {
        let dict: [String: Any] = [
            "Name": "/app/database/url",
            "Type": "String",
            "Version": 3,
            "Description": "Database connection URL",
            "Tier": "Standard",
            "DataType": "text",
            "ARN": "arn:aws:ssm:us-east-1:000:parameter/app/database/url",
            "LastModifiedDate": 1705312200.0,
        ]
        let param = SSMParameter(from: dict)
        #expect(param.name == "/app/database/url")
        #expect(param.type == "String")
        #expect(param.version == 3)
        #expect(param.description == "Database connection URL")
        #expect(param.tier == "Standard")
        #expect(param.lastModifiedDate != nil)
    }

    @Test("Defaults for missing parameter fields")
    func parseParameterDefaults() {
        let param = SSMParameter(from: [:])
        #expect(param.name == "")
        #expect(param.type == "String")
        #expect(param.version == 1)
        #expect(param.description == nil)
        #expect(param.lastModifiedDate == nil)
    }

    // MARK: - CLI

    @Test("getParameterCLI includes --with-decryption for SecureString")
    func getParameterCLISecure() {
        let param = SSMParameter(from: ["Name": "/key", "Type": "SecureString"])
        let cli = param.getParameterCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("--with-decryption"))
    }

    @Test("getParameterCLI omits --with-decryption for String")
    func getParameterCLIPlain() {
        let param = SSMParameter(from: ["Name": "/key", "Type": "String"])
        let cli = param.getParameterCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(!cli.contains("--with-decryption"))
    }

    @Test("describeParametersCLI generates valid command")
    func describeParametersCLI() {
        let param = SSMParameter(from: ["Name": "/app/key"])
        let cli = param.describeParametersCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ssm describe-parameters"))
        #expect(cli.contains("/app/key"))
    }

    // MARK: - SSMParameterValue

    @Test("isJSON detects JSON value")
    func isJSON() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Value": "{\"db\": \"url\"}"]])
        #expect(val.isJSON == true)
    }

    @Test("isJSON false for plain text")
    func isJSONFalse() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Value": "plain"]])
        #expect(val.isJSON == false)
    }

    @Test("isSecureString detects SecureString")
    func valueIsSecureString() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Type": "SecureString", "Value": "***"]])
        #expect(val.isSecureString == true)
    }

    @Test("prettyPrinted formats JSON value")
    func prettyPrinted() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Value": "{\"a\":1}"]])
        #expect(val.prettyPrinted != nil)
        #expect(val.prettyPrinted!.contains("\"a\" : 1"))
    }

    @Test("displayValue uses prettyPrinted for JSON")
    func displayValueJSON() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Value": "{\"a\":1}"]])
        #expect(val.displayValue.contains("\"a\" : 1"))
    }

    @Test("displayValue uses raw value for non-JSON")
    func displayValueRaw() {
        let val = SSMParameterValue(from: ["Parameter": ["Name": "/key", "Value": "plain text"]])
        #expect(val.displayValue == "plain text")
    }

    @Test("Parses from nested Parameter key")
    func parseNestedParameter() {
        let dict: [String: Any] = [
            "Parameter": [
                "Name": "/app/key",
                "Type": "String",
                "Value": "hello",
                "Version": 2,
                "ARN": "arn:ssm:param",
                "LastModifiedDate": 1705312200.0,
            ] as [String: Any]
        ]
        let val = SSMParameterValue(from: dict)
        #expect(val.name == "/app/key")
        #expect(val.value == "hello")
        #expect(val.version == 2)
        #expect(val.lastModifiedDate != nil)
    }

    @Test("Parses from flat dictionary (fallback)")
    func parseFlatDict() {
        let dict: [String: Any] = [
            "Name": "/key",
            "Type": "String",
            "Value": "val",
            "Version": 1,
        ]
        let val = SSMParameterValue(from: dict)
        #expect(val.name == "/key")
        #expect(val.value == "val")
    }
}
