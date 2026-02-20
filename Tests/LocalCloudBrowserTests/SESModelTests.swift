import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("SES Models")
struct SESModelTests {

    // MARK: - SESIdentity

    @Test("isEmail detects email addresses")
    func isEmail() {
        let email = SESIdentity(identity: "user@example.com")
        #expect(email.isEmail == true)

        let domain = SESIdentity(identity: "example.com")
        #expect(domain.isEmail == false)
    }

    @Test("typeBadge returns Email or Domain")
    func typeBadge() {
        #expect(SESIdentity(identity: "user@example.com").typeBadge == "Email")
        #expect(SESIdentity(identity: "example.com").typeBadge == "Domain")
    }

    // MARK: - SESIdentity CLI

    @Test("deleteIdentityCLI generates valid command")
    func deleteIdentityCLI() {
        let identity = SESIdentity(identity: "user@example.com")
        let cli = identity.deleteIdentityCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ses delete-identity"))
        #expect(cli.contains("user@example.com"))
    }

    @Test("listIdentitiesCLI generates valid command")
    func listIdentitiesCLI() {
        let cli = SESIdentity.listIdentitiesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ses list-identities"))
    }

    @Test("sendEmailCLI generates valid command")
    func sendEmailCLI() {
        let identity = SESIdentity(identity: "sender@example.com")
        let cli = identity.sendEmailCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws ses send-email"))
        #expect(cli.contains("sender@example.com"))
    }

    // MARK: - SESSentEmail.recipientSummary

    @Test("recipientSummary shows single recipient")
    func recipientSummarySingle() {
        let email = SESSentEmail(from: [
            "Id": "msg-1",
            "Source": "sender@example.com",
            "Destination": ["ToAddresses": ["alice@example.com"]],
        ])
        #expect(email.recipientSummary == "alice@example.com")
    }

    @Test("recipientSummary shows count for multiple recipients")
    func recipientSummaryMultiple() {
        let email = SESSentEmail(from: [
            "Id": "msg-1",
            "Source": "sender@example.com",
            "Destination": [
                "ToAddresses": ["alice@example.com", "bob@example.com"],
                "CcAddresses": ["charlie@example.com"],
            ],
        ])
        #expect(email.recipientSummary.contains("alice@example.com"))
        #expect(email.recipientSummary.contains("+2"))
    }

    @Test("recipientSummary returns dash for no recipients")
    func recipientSummaryEmpty() {
        let email = SESSentEmail(from: [
            "Id": "msg-1",
            "Source": "sender@example.com",
            "Destination": [:],
        ])
        #expect(email.recipientSummary == "—")
    }

    // MARK: - SESSentEmail body parsing

    @Test("parses nested Body.Text.Data format")
    func bodyNestedFormat() {
        let email = SESSentEmail(from: [
            "Id": "msg-1",
            "Source": "sender@example.com",
            "Body": [
                "Text": ["Data": "Hello"],
                "Html": ["Data": "<b>Hello</b>"],
            ],
        ])
        #expect(email.body.textData == "Hello")
        #expect(email.body.htmlData == "<b>Hello</b>")
    }

    @Test("parses flat Body format")
    func bodyFlatFormat() {
        let email = SESSentEmail(from: [
            "Id": "msg-1",
            "Source": "sender@example.com",
            "Body": [
                "text_data": "Hello",
                "html_data": "<b>Hello</b>",
            ],
        ])
        #expect(email.body.textData == "Hello")
        #expect(email.body.htmlData == "<b>Hello</b>")
    }
}
