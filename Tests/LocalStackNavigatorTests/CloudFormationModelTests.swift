import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("CloudFormation Models")
struct CloudFormationModelTests {

    // MARK: - CloudFormationStack.statusColor

    @Test("statusColor green for COMPLETE statuses")
    func statusColorGreen() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "CREATE_COMPLETE"])
        #expect(stack.statusColor == .green)

        let stack2 = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "UPDATE_COMPLETE"])
        #expect(stack2.statusColor == .green)
    }

    @Test("statusColor blue for IN_PROGRESS statuses")
    func statusColorBlue() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "CREATE_IN_PROGRESS"])
        #expect(stack.statusColor == .blue)
    }

    @Test("statusColor red for FAILED statuses")
    func statusColorRed() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "CREATE_FAILED"])
        #expect(stack.statusColor == .red)
    }

    @Test("statusColor orange for ROLLBACK statuses")
    func statusColorOrange() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "ROLLBACK_COMPLETE"])
        #expect(stack.statusColor == .orange)
    }

    @Test("statusColor gray for unknown statuses")
    func statusColorGray() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "SOMETHING"])
        #expect(stack.statusColor == .gray)
    }

    @Test("ROLLBACK_FAILED maps to red (FAILED takes priority over ROLLBACK)")
    func statusColorRollbackFailed() {
        let stack = CloudFormationStack(from: ["StackName": "s", "StackId": "id", "StackStatus": "ROLLBACK_FAILED"])
        // Contains both ROLLBACK and FAILED - the logic checks FAILED before ROLLBACK
        #expect(stack.statusColor == .red)
    }

    // MARK: - CloudFormationResource.shortType

    @Test("shortType strips AWS:: prefix")
    func shortType() {
        let resource = CloudFormationResource(from: [
            "LogicalResourceId": "MyBucket",
            "ResourceType": "AWS::S3::Bucket",
            "ResourceStatus": "CREATE_COMPLETE",
        ])
        #expect(resource.shortType == "S3::Bucket")
    }

    @Test("shortType returns original if no AWS:: prefix")
    func shortTypeNoPrefix() {
        let resource = CloudFormationResource(from: [
            "LogicalResourceId": "Custom",
            "ResourceType": "Custom::Resource",
            "ResourceStatus": "CREATE_COMPLETE",
        ])
        #expect(resource.shortType == "Custom::Resource")
    }

    // MARK: - CloudFormationStack.parseDate

    @Test("parseDate handles ISO8601 with fractional seconds")
    func parseDateFractional() {
        let date = CloudFormationStack.parseDate("2024-01-15T10:30:00.000Z")
        #expect(date != nil)
    }

    @Test("parseDate handles ISO8601 without fractional seconds")
    func parseDateNoFraction() {
        let date = CloudFormationStack.parseDate("2024-01-15T10:30:00Z")
        #expect(date != nil)
    }

    @Test("parseDate returns nil for nil input")
    func parseDateNil() {
        #expect(CloudFormationStack.parseDate(nil) == nil)
    }

    @Test("parseDate returns nil for invalid input")
    func parseDateInvalid() {
        #expect(CloudFormationStack.parseDate("not-a-date") == nil)
    }

    // MARK: - CFParameter

    @Test("CFParameter parses from dict")
    func cfParameterInit() {
        let param = CFParameter(from: ["ParameterKey": "Env", "ParameterValue": "prod"])
        #expect(param.parameterKey == "Env")
        #expect(param.parameterValue == "prod")
    }

    // MARK: - CFOutput

    @Test("CFOutput parses from dict")
    func cfOutputInit() {
        let output = CFOutput(from: [
            "OutputKey": "BucketArn",
            "OutputValue": "arn:aws:s3:::my-bucket",
            "Description": "The bucket ARN",
            "ExportName": "MyBucketArn",
        ])
        #expect(output.outputKey == "BucketArn")
        #expect(output.outputValue == "arn:aws:s3:::my-bucket")
        #expect(output.description == "The bucket ARN")
        #expect(output.exportName == "MyBucketArn")
    }

    // MARK: - CLI

    @Test("describeStackCLI generates valid command")
    func describeStackCLI() {
        let stack = CloudFormationStack(from: ["StackName": "my-stack", "StackId": "id", "StackStatus": "CREATE_COMPLETE"])
        let cli = stack.describeStackCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws cloudformation describe-stacks"))
        #expect(cli.contains("my-stack"))
    }

    @Test("listResourcesCLI generates valid command")
    func listResourcesCLI() {
        let stack = CloudFormationStack(from: ["StackName": "my-stack", "StackId": "id", "StackStatus": "CREATE_COMPLETE"])
        let cli = stack.listResourcesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws cloudformation list-stack-resources"))
    }
}
