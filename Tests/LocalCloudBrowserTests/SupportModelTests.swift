import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Support Models")
struct SupportModelTests {

    // MARK: - SupportCase.timeCreatedDate

    @Test("timeCreatedDate parses epoch string")
    func timeCreatedDate() {
        let c = SupportCase(timeCreated: "1700000000")
        #expect(c.timeCreatedDate != nil)
    }

    @Test("timeCreatedDate nil for non-numeric string")
    func timeCreatedDateNil() {
        let c = SupportCase(timeCreated: "not-a-number")
        #expect(c.timeCreatedDate == nil)
    }

    @Test("timeCreatedDate nil for empty string")
    func timeCreatedDateEmpty() {
        let c = SupportCase(timeCreated: "")
        #expect(c.timeCreatedDate == nil)
    }

    // MARK: - statusDisplayName

    @Test("statusDisplayName maps known statuses")
    func statusDisplayName() {
        #expect(SupportCase(status: "resolved").statusDisplayName == "Resolved")
        #expect(SupportCase(status: "unresolved").statusDisplayName == "Unresolved")
        #expect(SupportCase(status: "pending-customer-action").statusDisplayName == "Pending")
        #expect(SupportCase(status: "reopened").statusDisplayName == "Reopened")
        #expect(SupportCase(status: "work-in-progress").statusDisplayName == "In Progress")
    }

    @Test("statusDisplayName returns raw for unknown status")
    func statusDisplayNameUnknown() {
        #expect(SupportCase(status: "custom-status").statusDisplayName == "custom-status")
    }

    // MARK: - init(from:)

    @Test("parses from dict with string timeCreated")
    func initFromDictString() {
        let c = SupportCase(from: [
            "caseId": "case-123",
            "displayId": "D-123",
            "subject": "Help needed",
            "status": "unresolved",
            "severityCode": "normal",
            "timeCreated": "1700000000",
        ])
        #expect(c.caseId == "case-123")
        #expect(c.displayId == "D-123")
        #expect(c.subject == "Help needed")
        #expect(c.timeCreated == "1700000000")
    }

    @Test("parses from dict with numeric timeCreated")
    func initFromDictNumeric() {
        let c = SupportCase(from: [
            "caseId": "case-123",
            "timeCreated": 1700000000.0,
        ])
        #expect(c.timeCreated == "1700000000.0")
    }

    // MARK: - SupportCaseDetail

    @Test("parses communications from nested dict")
    func caseDetailInit() {
        let detail = SupportCaseDetail(from: [
            "caseId": "case-123",
            "subject": "Test",
            "status": "unresolved",
            "recentCommunications": [
                "communications": [
                    ["body": "Hello", "submittedBy": "user@example.com", "timeCreated": "1700000000"],
                    ["body": "Reply", "submittedBy": "support@aws.com", "timeCreated": "1700001000"],
                ],
            ],
        ])
        #expect(detail.communications.count == 2)
        #expect(detail.communications[0].body == "Hello")
        #expect(detail.communications[1].submittedBy == "support@aws.com")
    }

    // MARK: - SupportCommunication

    @Test("timeCreatedDate parses epoch")
    func communicationTimeCreated() {
        let comm = SupportCommunication(timeCreated: "1700000000")
        #expect(comm.timeCreatedDate != nil)
    }

    @Test("parses from dict with numeric timeCreated")
    func communicationFromDictNumeric() {
        let comm = SupportCommunication(from: [
            "body": "test",
            "timeCreated": 1700000000.0,
        ])
        #expect(comm.timeCreated == "1700000000.0")
    }

    // MARK: - CLI

    @Test("describeCaseCLI generates valid command")
    func describeCaseCLI() {
        let c = SupportCase(caseId: "case-123")
        let cli = c.describeCaseCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws support describe-cases"))
        #expect(cli.contains("case-123"))
        #expect(cli.contains("--include-communications"))
    }

    @Test("resolveCaseCLI generates valid command")
    func resolveCaseCLI() {
        let c = SupportCase(caseId: "case-123")
        let cli = c.resolveCaseCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws support resolve-case"))
    }

    @Test("listCasesCLI generates valid command")
    func listCasesCLI() {
        let cli = SupportCase.listCasesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws support describe-cases"))
    }
}
