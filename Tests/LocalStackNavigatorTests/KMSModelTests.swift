import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("KMS Models")
struct KMSModelTests {

    // MARK: - KMSKey.truncatedId

    @Test("truncatedId truncates long IDs")
    func truncatedId() {
        let key = KMSKey(keyId: "abcdefgh-1234-5678-9012-abcdefghijkl")
        #expect(key.truncatedId == "abcdefgh...")
    }

    @Test("truncatedId returns short IDs as-is")
    func truncatedIdShort() {
        let key = KMSKey(keyId: "abc")
        #expect(key.truncatedId == "abc")
    }

    // MARK: - stateBadgeColor

    @Test("stateBadgeColor maps states correctly")
    func stateBadgeColor() {
        #expect(KMSKey(keyState: "Enabled").stateBadgeColor == "green")
        #expect(KMSKey(keyState: "Disabled").stateBadgeColor == "orange")
        #expect(KMSKey(keyState: "PendingDeletion").stateBadgeColor == "red")
        #expect(KMSKey(keyState: "Unknown").stateBadgeColor == "gray")
    }

    // MARK: - init(from:)

    @Test("KMSKey parses from dict")
    func initFromDict() {
        let key = KMSKey(from: [
            "KeyId": "abc-123",
            "Arn": "arn:aws:kms:us-east-1:000:key/abc-123",
            "Description": "My key",
            "Enabled": true,
            "KeyState": "Enabled",
            "KeyUsage": "ENCRYPT_DECRYPT",
            "KeySpec": "SYMMETRIC_DEFAULT",
            "KeyManager": "CUSTOMER",
            "Origin": "AWS_KMS",
            "CreationDate": 1700000000.0,
        ])
        #expect(key.keyId == "abc-123")
        #expect(key.description == "My key")
        #expect(key.enabled == true)
        #expect(key.keyManager == "CUSTOMER")
        #expect(key.creationDate != nil)
    }

    @Test("KMSKey defaults for missing fields")
    func initDefaults() {
        let key = KMSKey(from: [:])
        #expect(key.keyId == "")
        #expect(key.enabled == true)
        #expect(key.keyState == "Enabled")
        #expect(key.keyUsage == "ENCRYPT_DECRYPT")
        #expect(key.keySpec == "SYMMETRIC_DEFAULT")
    }

    // MARK: - KMSAlias

    @Test("KMSAlias parses from dict")
    func aliasInit() {
        let alias = KMSAlias(from: [
            "AliasName": "alias/my-key",
            "AliasArn": "arn:aws:kms:us-east-1:000:alias/my-key",
            "TargetKeyId": "abc-123",
        ])
        #expect(alias.aliasName == "alias/my-key")
        #expect(alias.targetKeyId == "abc-123")
    }

    // MARK: - CLI

    @Test("describeKeyCLI generates valid command")
    func describeKeyCLI() {
        let key = KMSKey(keyId: "abc-123")
        let cli = key.describeKeyCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws kms describe-key"))
        #expect(cli.contains("abc-123"))
    }

    @Test("listKeysCLI generates valid command")
    func listKeysCLI() {
        let cli = KMSKey.listKeysCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws kms list-keys"))
    }
}
