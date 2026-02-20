import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("EventBridge Models")
struct EventBridgeModelTests {

    // MARK: - EventBridgeBus

    @Test("isDefault for default bus")
    func busIsDefault() {
        let bus = EventBridgeBus(from: ["Name": "default"])
        #expect(bus.isDefault == true)

        let custom = EventBridgeBus(from: ["Name": "my-bus"])
        #expect(custom.isDefault == false)
    }

    // MARK: - EventBridgeRule

    @Test("isEnabled when state is ENABLED")
    func ruleIsEnabled() {
        let rule = EventBridgeRule(from: ["Name": "r1", "State": "ENABLED"])
        #expect(rule.isEnabled == true)

        let disabled = EventBridgeRule(from: ["Name": "r2", "State": "DISABLED"])
        #expect(disabled.isEnabled == false)
    }

    @Test("ruleType detects event pattern")
    func ruleTypeEventPattern() {
        let rule = EventBridgeRule(from: [
            "Name": "r1",
            "EventPattern": "{\"source\": [\"aws.s3\"]}",
        ])
        #expect(rule.ruleType == .eventPattern)
        #expect(rule.ruleType.displayName == "Event Pattern")
    }

    @Test("ruleType detects schedule")
    func ruleTypeSchedule() {
        let rule = EventBridgeRule(from: [
            "Name": "r1",
            "ScheduleExpression": "rate(5 minutes)",
        ])
        #expect(rule.ruleType == .schedule)
        #expect(rule.ruleType.displayName == "Schedule")
    }

    @Test("ruleType unknown when neither pattern nor schedule")
    func ruleTypeUnknown() {
        let rule = EventBridgeRule(from: ["Name": "r1"])
        #expect(rule.ruleType == .unknown)
    }

    @Test("prettyEventPattern formats JSON")
    func prettyEventPattern() {
        let rule = EventBridgeRule(from: [
            "Name": "r1",
            "EventPattern": "{\"source\":[\"aws.s3\"]}",
        ])
        #expect(rule.prettyEventPattern != nil)
        #expect(rule.prettyEventPattern!.contains("source"))
    }

    // MARK: - EventBridgeTarget

    @Test("prettyInput formats JSON")
    func targetPrettyInput() {
        let target = EventBridgeTarget(from: [
            "Id": "t1",
            "Arn": "arn:aws:lambda:us-east-1:000:function:my-func",
            "Input": "{\"key\":\"value\"}",
        ])
        #expect(target.prettyInput != nil)
        #expect(target.prettyInput!.contains("key"))
    }

    @Test("prettyInput returns raw for non-JSON")
    func targetPrettyInputNonJSON() {
        let target = EventBridgeTarget(from: [
            "Id": "t1",
            "Arn": "arn:test",
            "Input": "plain text",
        ])
        #expect(target.prettyInput == "plain text")
    }

    @Test("deadLetterArn parsed from DeadLetterConfig")
    func targetDeadLetterArn() {
        let target = EventBridgeTarget(from: [
            "Id": "t1",
            "Arn": "arn:test",
            "DeadLetterConfig": ["Arn": "arn:aws:sqs:us-east-1:000:dlq"],
        ])
        #expect(target.deadLetterArn == "arn:aws:sqs:us-east-1:000:dlq")
    }

    // MARK: - SchedulerTargetServiceType

    @Test("from(arn:) detects Lambda")
    func targetServiceLambda() {
        let t = SchedulerTargetServiceType.from(arn: "arn:aws:lambda:us-east-1:000:function:my-func")
        #expect(t == .lambda)
        #expect(t.displayName == "Lambda")
    }

    @Test("from(arn:) detects Step Functions")
    func targetServiceStepFunctions() {
        let t = SchedulerTargetServiceType.from(arn: "arn:aws:states:us-east-1:000:stateMachine:my-sm")
        #expect(t == .stepFunctions)
    }

    @Test("from(arn:) detects SQS and SNS")
    func targetServiceSQSSNS() {
        #expect(SchedulerTargetServiceType.from(arn: "arn:aws:sqs:us-east-1:000:my-queue") == .sqs)
        #expect(SchedulerTargetServiceType.from(arn: "arn:aws:sns:us-east-1:000:my-topic") == .sns)
    }

    @Test("from(arn:) returns other for unknown service")
    func targetServiceOther() {
        let t = SchedulerTargetServiceType.from(arn: "arn:aws:ec2:us-east-1:000:instance/i-123")
        #expect(t.displayName == "ec2")
    }

    @Test("from(arn:) returns Unknown for short ARN")
    func targetServiceShortArn() {
        let t = SchedulerTargetServiceType.from(arn: "arn:aws")
        #expect(t.displayName == "Unknown")
    }

    // MARK: - SchedulerSchedule

    @Test("isEnabled when state is ENABLED")
    func scheduleIsEnabled() {
        let schedule = SchedulerSchedule(from: ["Name": "s1", "State": "ENABLED"])
        #expect(schedule.isEnabled == true)

        let disabled = SchedulerSchedule(from: ["Name": "s2", "State": "DISABLED"])
        #expect(disabled.isEnabled == false)
    }

    @Test("targetServiceType derived from target ARN")
    func scheduleTargetServiceType() {
        let schedule = SchedulerSchedule(from: [
            "Name": "s1",
            "Target": ["Arn": "arn:aws:lambda:us-east-1:000:function:my-func"],
        ])
        #expect(schedule.targetServiceType == .lambda)
    }

    // MARK: - SchedulerScheduleGroup

    @Test("isDefault for default group")
    func scheduleGroupIsDefault() {
        let group = SchedulerScheduleGroup(from: ["Name": "default"])
        #expect(group.isDefault == true)

        let custom = SchedulerScheduleGroup(from: ["Name": "my-group"])
        #expect(custom.isDefault == false)
    }

    // MARK: - CLI

    @Test("listRulesCLI generates valid command")
    func listRulesCLI() {
        let bus = EventBridgeBus(from: ["Name": "default"])
        let cli = bus.listRulesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws events list-rules"))
        #expect(cli.contains("default"))
    }

    @Test("describeRuleCLI generates valid command")
    func describeRuleCLI() {
        let rule = EventBridgeRule(from: [
            "Name": "my-rule",
            "EventBusName": "custom-bus",
        ])
        let cli = rule.describeRuleCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws events describe-rule"))
        #expect(cli.contains("my-rule"))
        #expect(cli.contains("custom-bus"))
    }

    // MARK: - PutEventsResult

    @Test("PutEventsResult parses entries")
    func putEventsResult() {
        let result = PutEventsResult(from: [
            "FailedEntryCount": 1,
            "Entries": [
                ["EventId": "e1"],
                ["ErrorCode": "InternalError", "ErrorMessage": "fail"],
            ],
        ])
        #expect(result.failedEntryCount == 1)
        #expect(result.entries.count == 2)
        #expect(result.entries[0].eventId == "e1")
        #expect(result.entries[1].errorCode == "InternalError")
    }
}
