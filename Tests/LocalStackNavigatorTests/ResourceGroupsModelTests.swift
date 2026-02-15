import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("Resource Groups Models")
struct ResourceGroupsModelTests {

    // MARK: - ResourceGroupSummary

    @Test("parses from dict with nested Group")
    func summaryInitNested() {
        let group = ResourceGroupSummary(from: [
            "Group": [
                "Name": "my-group",
                "GroupArn": "arn:aws:resource-groups:us-east-1:000:group/my-group",
                "Description": "Test group",
            ],
        ])
        #expect(group.name == "my-group")
        #expect(group.groupArn == "arn:aws:resource-groups:us-east-1:000:group/my-group")
        #expect(group.description == "Test group")
    }

    @Test("parses from flat dict")
    func summaryInitFlat() {
        let group = ResourceGroupSummary(from: [
            "GroupName": "my-group",
            "GroupArn": "arn:test",
            "Description": "Flat format",
        ])
        #expect(group.name == "my-group")
    }

    // MARK: - GroupResource.shortTypeLabel

    @Test("shortTypeLabel extracts service and resource")
    func shortTypeLabel() {
        let resource = GroupResource(resourceType: "AWS::S3::Bucket")
        #expect(resource.shortTypeLabel == "S3 Bucket")
    }

    @Test("shortTypeLabel returns raw type if not enough parts")
    func shortTypeLabelShort() {
        let resource = GroupResource(resourceType: "Custom")
        #expect(resource.shortTypeLabel == "Custom")
    }

    // MARK: - GroupResource.typeColor

    @Test("typeColor detects S3")
    func typeColorS3() {
        let resource = GroupResource(resourceType: "AWS::S3::Bucket")
        #expect(resource.typeColor.label == "S3")
        #expect(resource.typeColor.color == "green")
    }

    @Test("typeColor detects Lambda")
    func typeColorLambda() {
        let resource = GroupResource(resourceType: "AWS::Lambda::Function")
        #expect(resource.typeColor.label == "Lambda")
        #expect(resource.typeColor.color == "orange")
    }

    @Test("typeColor detects DynamoDB")
    func typeColorDynamoDB() {
        let resource = GroupResource(resourceType: "AWS::DynamoDB::Table")
        #expect(resource.typeColor.label == "DynamoDB")
        #expect(resource.typeColor.color == "blue")
    }

    @Test("typeColor defaults to AWS/gray for unknown")
    func typeColorDefault() {
        let resource = GroupResource(resourceType: "AWS::CloudFront::Distribution")
        #expect(resource.typeColor.label == "AWS")
        #expect(resource.typeColor.color == "gray")
    }

    // MARK: - GroupResource.init(from:)

    @Test("parses from dict with ResourceArn")
    func resourceInitDirect() {
        let resource = GroupResource(from: [
            "ResourceArn": "arn:aws:s3:::my-bucket",
            "ResourceType": "AWS::S3::Bucket",
        ])
        #expect(resource.resourceArn == "arn:aws:s3:::my-bucket")
        #expect(resource.resourceType == "AWS::S3::Bucket")
    }

    @Test("parses from dict with nested Identifier")
    func resourceInitNested() {
        let resource = GroupResource(from: [
            "Identifier": [
                "ResourceArn": "arn:aws:lambda:us-east-1:000:function:my-func",
                "ResourceType": "AWS::Lambda::Function",
            ],
            "Status": ["Name": "COMPLETE"],
        ])
        #expect(resource.resourceArn.contains("my-func"))
        #expect(resource.resourceType == "AWS::Lambda::Function")
        #expect(resource.status == "COMPLETE")
    }

    // MARK: - ResourceGroupQuery

    @Test("parses from dict with JSON Query string")
    func queryInit() {
        let queryJSON = """
        {"TagFilters":[{"Key":"env","Values":["prod","staging"]}],"ResourceTypeFilters":["AWS::S3::Bucket"]}
        """
        let query = ResourceGroupQuery(from: [
            "Type": "TAG_FILTERS_1_0",
            "Query": queryJSON,
        ])
        #expect(query.type == "TAG_FILTERS_1_0")
        #expect(query.tagFilters.count == 1)
        #expect(query.tagFilters[0].key == "env")
        #expect(query.tagFilters[0].values == ["prod", "staging"])
        #expect(query.resourceTypeFilters == ["AWS::S3::Bucket"])
    }

    // MARK: - CLI

    @Test("getGroupCLI generates valid command")
    func getGroupCLI() {
        let group = ResourceGroupSummary(name: "my-group")
        let cli = group.getGroupCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws resource-groups get-group"))
        #expect(cli.contains("my-group"))
    }

    @Test("listGroupsCLI generates valid command")
    func listGroupsCLI() {
        let cli = ResourceGroupSummary.listGroupsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws resource-groups list-groups"))
    }
}
