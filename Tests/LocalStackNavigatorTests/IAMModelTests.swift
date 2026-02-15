import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("IAM Models")
struct IAMModelTests {

    // MARK: - IAMUser

    @Test("IAMUser parses from dict")
    func userInit() {
        let user = IAMUser(from: [
            "UserName": "admin",
            "UserId": "AIDAEXAMPLE",
            "Arn": "arn:aws:iam::000:user/admin",
            "Path": "/",
            "CreateDate": "2024-01-15T10:30:00Z",
        ])
        #expect(user.userName == "admin")
        #expect(user.userId == "AIDAEXAMPLE")
        #expect(user.path == "/")
        #expect(user.createDate != nil)
    }

    @Test("IAMUser parseDate handles fractional seconds")
    func userParseDateFractional() {
        let date = IAMUser.parseDate("2024-01-15T10:30:00.123Z")
        #expect(date != nil)
    }

    @Test("IAMUser parseDate returns nil for nil")
    func userParseDateNil() {
        #expect(IAMUser.parseDate(nil) == nil)
    }

    // MARK: - IAMRole

    @Test("IAMRole prettyTrustPolicy formats JSON")
    func rolePrettyTrustPolicy() {
        let encoded = "%7B%22Version%22%3A%222012-10-17%22%7D"
        let role = IAMRole(from: [
            "RoleName": "test-role",
            "RoleId": "AROAEXAMPLE",
            "Path": "/",
            "AssumeRolePolicyDocument": encoded,
        ])
        let pretty = role.prettyTrustPolicy
        #expect(pretty != nil)
        #expect(pretty!.contains("Version"))
    }

    @Test("IAMRole prettyTrustPolicy nil when no document")
    func rolePrettyTrustPolicyNil() {
        let role = IAMRole(from: ["RoleName": "test", "RoleId": "R", "Path": "/"])
        #expect(role.prettyTrustPolicy == nil)
    }

    @Test("IAMRole parses maxSessionDuration")
    func roleMaxSessionDuration() {
        let role = IAMRole(from: [
            "RoleName": "test",
            "RoleId": "R",
            "Path": "/",
            "MaxSessionDuration": "7200",
        ])
        #expect(role.maxSessionDuration == 7200)
    }

    // MARK: - IAMPolicy

    @Test("IAMPolicy isAWSManaged")
    func policyIsAWSManaged() {
        let managed = IAMPolicy(from: [
            "PolicyName": "ReadOnly",
            "PolicyId": "P1",
            "Arn": "arn:aws:iam::aws:policy/ReadOnlyAccess",
            "Path": "/",
        ])
        #expect(managed.isAWSManaged == true)

        let custom = IAMPolicy(from: [
            "PolicyName": "Custom",
            "PolicyId": "P2",
            "Arn": "arn:aws:iam::000:policy/Custom",
            "Path": "/",
        ])
        #expect(custom.isAWSManaged == false)
    }

    @Test("IAMPolicy parses attachmentCount")
    func policyAttachmentCount() {
        let policy = IAMPolicy(from: [
            "PolicyName": "test",
            "PolicyId": "P",
            "Arn": "arn:aws:iam::000:policy/test",
            "Path": "/",
            "AttachmentCount": "5",
        ])
        #expect(policy.attachmentCount == 5)
    }

    // MARK: - IAMGroup

    @Test("IAMGroup parses from dict")
    func groupInit() {
        let group = IAMGroup(from: [
            "GroupName": "admins",
            "GroupId": "AGPAEXAMPLE",
            "Arn": "arn:aws:iam::000:group/admins",
            "Path": "/",
        ])
        #expect(group.groupName == "admins")
        #expect(group.groupId == "AGPAEXAMPLE")
    }

    // MARK: - CLI

    @Test("getUserCLI generates valid command")
    func getUserCLI() {
        let user = IAMUser(from: ["UserName": "admin", "UserId": "U", "Path": "/"])
        let cli = user.getUserCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws iam get-user"))
        #expect(cli.contains("admin"))
    }

    @Test("getRoleCLI generates valid command")
    func getRoleCLI() {
        let role = IAMRole(from: ["RoleName": "my-role", "RoleId": "R", "Path": "/"])
        let cli = role.getRoleCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws iam get-role"))
        #expect(cli.contains("my-role"))
    }

    @Test("getPolicyCLI generates valid command")
    func getPolicyCLI() {
        let policy = IAMPolicy(from: [
            "PolicyName": "my-policy",
            "PolicyId": "P",
            "Arn": "arn:aws:iam::000:policy/my-policy",
            "Path": "/",
        ])
        let cli = policy.getPolicyCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws iam get-policy"))
        #expect(cli.contains("arn:aws:iam::000:policy/my-policy"))
    }
}
