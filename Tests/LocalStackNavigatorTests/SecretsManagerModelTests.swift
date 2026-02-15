import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("Secrets Manager Models")
struct SecretsManagerModelTests {

    // MARK: - Secret init(from:)

    @Test("Parses secret from dictionary")
    func parseSecret() {
        let dict: [String: Any] = [
            "ARN": "arn:aws:secretsmanager:us-east-1:000:secret:my-secret",
            "Name": "my-secret",
            "Description": "A test secret",
            "CreatedDate": 1705312200.0,
            "LastChangedDate": 1705398600.0,
            "Tags": [
                ["Key": "env", "Value": "production"],
                ["Key": "team", "Value": "backend"],
            ],
        ]
        let secret = Secret(from: dict)
        #expect(secret.name == "my-secret")
        #expect(secret.description == "A test secret")
        #expect(secret.createdDate != nil)
        #expect(secret.lastChangedDate != nil)
        #expect(secret.tags["env"] == "production")
        #expect(secret.tags["team"] == "backend")
    }

    @Test("Defaults for missing secret fields")
    func parseSecretDefaults() {
        let secret = Secret(from: [:])
        #expect(secret.arn == "")
        #expect(secret.name == "")
        #expect(secret.description == nil)
        #expect(secret.createdDate == nil)
        #expect(secret.tags.isEmpty)
    }

    // MARK: - CLI

    @Test("getSecretValueCLI generates valid command")
    func getSecretValueCLI() {
        let secret = Secret(from: ["ARN": "arn:secret", "Name": "my-secret"])
        let cli = secret.getSecretValueCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws secretsmanager get-secret-value"))
        #expect(cli.contains("my-secret"))
    }

    @Test("describeSecretCLI generates valid command")
    func describeSecretCLI() {
        let secret = Secret(from: ["ARN": "arn:secret", "Name": "my-secret"])
        let cli = secret.describeSecretCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws secretsmanager describe-secret"))
    }

    @Test("CLI escapes single quotes in secret name")
    func cliEscapes() {
        let secret = Secret(from: ["ARN": "arn", "Name": "it's-secret"])
        let cli = secret.getSecretValueCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("'\\''"))
    }

    // MARK: - SecretValue

    @Test("isJSON detects JSON secret string")
    func isJSON() {
        let val = SecretValue(from: ["SecretString": "{\"key\": \"val\"}"])
        #expect(val.isJSON == true)
    }

    @Test("isJSON false for plain text")
    func isJSONFalse() {
        let val = SecretValue(from: ["SecretString": "plain text"])
        #expect(val.isJSON == false)
    }

    @Test("isJSON false when secretString is nil")
    func isJSONNil() {
        let val = SecretValue(from: [:])
        #expect(val.isJSON == false)
    }

    @Test("prettyPrinted formats JSON")
    func prettyPrinted() {
        let val = SecretValue(from: ["SecretString": "{\"a\":1}"])
        #expect(val.prettyPrinted != nil)
        #expect(val.prettyPrinted!.contains("\"a\" : 1"))
    }

    @Test("prettyPrinted nil for non-JSON")
    func prettyPrintedNil() {
        let val = SecretValue(from: ["SecretString": "not json"])
        #expect(val.prettyPrinted == nil)
    }

    @Test("displayValue uses prettyPrinted when available")
    func displayValueJSON() {
        let val = SecretValue(from: ["SecretString": "{\"a\":1}"])
        #expect(val.displayValue.contains("\"a\" : 1"))
    }

    @Test("displayValue falls back to raw string")
    func displayValueRaw() {
        let val = SecretValue(from: ["SecretString": "raw secret"])
        #expect(val.displayValue == "raw secret")
    }

    @Test("displayValue falls back to binary")
    func displayValueBinary() {
        let val = SecretValue(from: ["SecretBinary": "base64data"])
        #expect(val.displayValue == "base64data")
    }

    @Test("displayValue empty when nothing set")
    func displayValueEmpty() {
        let val = SecretValue(from: [:])
        #expect(val.displayValue == "")
    }

    // MARK: - SecretDetail

    @Test("Parses secret detail with versions and rotation")
    func parseSecretDetail() {
        let dict: [String: Any] = [
            "ARN": "arn:secret",
            "Name": "my-secret",
            "RotationEnabled": true,
            "VersionIdsToStages": ["v1": ["AWSCURRENT"], "v2": ["AWSPREVIOUS"]],
            "Tags": [["Key": "env", "Value": "prod"]],
        ]
        let detail = SecretDetail(from: dict)
        #expect(detail.rotationEnabled == true)
        #expect(detail.versionIdsToStages.count == 2)
        #expect(detail.tags["env"] == "prod")
    }
}
