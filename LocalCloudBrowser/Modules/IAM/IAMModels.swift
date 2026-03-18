import Foundation
import SwiftUI

struct IAMUser: Identifiable, Hashable {
    let userName: String
    let userId: String
    let arn: String?
    let path: String
    let createDate: Date?

    var id: String { userName }

    func getUserCLI(endpointUrl: String, region: String) -> String {
        [
            "aws iam get-user \\",
            "  --user-name '\(userName.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func parseDate(_ string: String?) -> Date? {
        DateFormatters.parseISO8601(string)
    }

    init(from dict: [String: String]) {
        userName = dict["UserName"] ?? ""
        userId = dict["UserId"] ?? ""
        arn = dict["Arn"]
        path = dict["Path"] ?? "/"
        createDate = Self.parseDate(dict["CreateDate"])
    }
}

struct IAMRole: Identifiable, Hashable {
    let roleName: String
    let roleId: String
    let arn: String?
    let path: String
    let createDate: Date?
    let assumeRolePolicyDocument: String?
    let description: String?
    let maxSessionDuration: Int?

    var id: String { roleName }

    var prettyTrustPolicy: String? {
        guard let doc = assumeRolePolicyDocument,
              let decoded = doc.removingPercentEncoding,
              let data = decoded.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return assumeRolePolicyDocument?.removingPercentEncoding
        }
        return result
    }

    func getRoleCLI(endpointUrl: String, region: String) -> String {
        [
            "aws iam get-role \\",
            "  --role-name '\(roleName.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from dict: [String: String]) {
        roleName = dict["RoleName"] ?? ""
        roleId = dict["RoleId"] ?? ""
        arn = dict["Arn"]
        path = dict["Path"] ?? "/"
        createDate = IAMUser.parseDate(dict["CreateDate"])
        assumeRolePolicyDocument = dict["AssumeRolePolicyDocument"]
        description = dict["Description"]
        if let dur = dict["MaxSessionDuration"] {
            maxSessionDuration = Int(dur)
        } else {
            maxSessionDuration = nil
        }
    }
}

struct IAMPolicy: Identifiable, Hashable {
    let policyName: String
    let policyId: String
    let arn: String
    let path: String
    let defaultVersionId: String?
    let attachmentCount: Int
    let createDate: Date?
    let updateDate: Date?
    let description: String?

    var id: String { arn }

    var isAWSManaged: Bool {
        arn.hasPrefix("arn:aws:iam::aws:policy/")
    }

    func getPolicyCLI(endpointUrl: String, region: String) -> String {
        [
            "aws iam get-policy \\",
            "  --policy-arn '\(arn.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from dict: [String: String]) {
        policyName = dict["PolicyName"] ?? ""
        policyId = dict["PolicyId"] ?? ""
        arn = dict["Arn"] ?? ""
        path = dict["Path"] ?? "/"
        defaultVersionId = dict["DefaultVersionId"]
        attachmentCount = Int(dict["AttachmentCount"] ?? "0") ?? 0
        createDate = IAMUser.parseDate(dict["CreateDate"])
        updateDate = IAMUser.parseDate(dict["UpdateDate"])
        description = dict["Description"]
    }
}

struct IAMAttachedPolicy: Identifiable, Hashable {
    let policyName: String
    let policyArn: String

    var id: String { policyArn }

    init(from dict: [String: String]) {
        policyName = dict["PolicyName"] ?? ""
        policyArn = dict["PolicyArn"] ?? ""
    }
}

struct IAMGroup: Identifiable, Hashable {
    let groupName: String
    let groupId: String
    let arn: String?
    let path: String
    let createDate: Date?

    var id: String { groupName }

    init(from dict: [String: String]) {
        groupName = dict["GroupName"] ?? ""
        groupId = dict["GroupId"] ?? ""
        arn = dict["Arn"]
        path = dict["Path"] ?? "/"
        createDate = IAMUser.parseDate(dict["CreateDate"])
    }
}

/// Represents which type of IAM entity is active for selection.
enum IAMEntityType: String, CaseIterable {
    case users = "Users"
    case roles = "Roles"
    case policies = "Policies"
}
