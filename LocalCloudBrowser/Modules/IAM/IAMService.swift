import Foundation

final class IAMService: BaseService {
    // MARK: - Users

    func listUsersPage(token: String? = nil) async throws -> ([IAMUser], String?) {
        var params: [String: String] = [:]
        if let token {
            params["Marker"] = token
        }
        let data = try await client.iamRequest(action: "ListUsers", params: params)
        let xml = try SNSXMLParser.parse(data)
        let users = xml.memberDicts.map { IAMUser(from: $0) }
        let next = xml.first("IsTruncated") == "true" ? xml.first("Marker") : nil
        return (users, next)
    }

    func listUsers() async throws -> [IAMUser] {
        var allUsers: [IAMUser] = []
        var marker: String? = nil
        repeat {
            let (users, token) = try await listUsersPage(token: marker)
            allUsers.append(contentsOf: users)
            marker = token
            if allUsers.count >= 10_000 { break }
        } while marker != nil
        return allUsers
    }

    func createUser(userName: String) async throws {
        _ = try await client.iamRequest(
            action: "CreateUser",
            params: ["UserName": userName]
        )
    }

    func deleteUser(userName: String) async throws {
        // Detach all policies first
        let attached = try await listAttachedUserPolicies(userName: userName)
        for policy in attached {
            try await detachUserPolicy(userName: userName, policyArn: policy.policyArn)
        }
        // Remove from all groups
        let groups = try await listGroupsForUser(userName: userName)
        for group in groups {
            try await removeUserFromGroup(userName: userName, groupName: group.groupName)
        }
        _ = try await client.iamRequest(
            action: "DeleteUser",
            params: ["UserName": userName]
        )
    }

    func listAttachedUserPolicies(userName: String) async throws -> [IAMAttachedPolicy] {
        var allPolicies: [IAMAttachedPolicy] = []
        var marker: String? = nil

        repeat {
            var params: [String: String] = ["UserName": userName]
            if let m = marker {
                params["Marker"] = m
            }
            let data = try await client.iamRequest(action: "ListAttachedUserPolicies", params: params)
            let xml = try SNSXMLParser.parse(data)

            for member in xml.memberDicts {
                allPolicies.append(IAMAttachedPolicy(from: member))
            }
            if xml.first("IsTruncated") == "true" {
                marker = xml.first("Marker")
            } else {
                marker = nil
            }
            if allPolicies.count >= 10_000 { break }
        } while marker != nil

        return allPolicies
    }

    func attachUserPolicy(userName: String, policyArn: String) async throws {
        _ = try await client.iamRequest(
            action: "AttachUserPolicy",
            params: ["UserName": userName, "PolicyArn": policyArn]
        )
    }

    func detachUserPolicy(userName: String, policyArn: String) async throws {
        _ = try await client.iamRequest(
            action: "DetachUserPolicy",
            params: ["UserName": userName, "PolicyArn": policyArn]
        )
    }

    func listGroupsForUser(userName: String) async throws -> [IAMGroup] {
        var allGroups: [IAMGroup] = []
        var marker: String? = nil

        repeat {
            var params: [String: String] = ["UserName": userName]
            if let m = marker {
                params["Marker"] = m
            }
            let data = try await client.iamRequest(action: "ListGroupsForUser", params: params)
            let xml = try SNSXMLParser.parse(data)

            for member in xml.memberDicts {
                allGroups.append(IAMGroup(from: member))
            }
            if xml.first("IsTruncated") == "true" {
                marker = xml.first("Marker")
            } else {
                marker = nil
            }
            if allGroups.count >= 10_000 { break }
        } while marker != nil

        return allGroups
    }

    func addUserToGroup(userName: String, groupName: String) async throws {
        _ = try await client.iamRequest(
            action: "AddUserToGroup",
            params: ["UserName": userName, "GroupName": groupName]
        )
    }

    func removeUserFromGroup(userName: String, groupName: String) async throws {
        _ = try await client.iamRequest(
            action: "RemoveUserFromGroup",
            params: ["UserName": userName, "GroupName": groupName]
        )
    }

    // MARK: - Roles

    func listRolesPage(token: String? = nil) async throws -> ([IAMRole], String?) {
        var params: [String: String] = [:]
        if let token {
            params["Marker"] = token
        }
        let data = try await client.iamRequest(action: "ListRoles", params: params)
        let xml = try SNSXMLParser.parse(data)
        let roles = xml.memberDicts.map { IAMRole(from: $0) }
        let next = xml.first("IsTruncated") == "true" ? xml.first("Marker") : nil
        return (roles, next)
    }

    func listRoles() async throws -> [IAMRole] {
        var allRoles: [IAMRole] = []
        var marker: String? = nil
        repeat {
            let (roles, token) = try await listRolesPage(token: marker)
            allRoles.append(contentsOf: roles)
            marker = token
            if allRoles.count >= 10_000 { break }
        } while marker != nil
        return allRoles
    }

    func createRole(roleName: String, assumeRolePolicyDocument: String, description: String?) async throws {
        var params: [String: String] = [
            "RoleName": roleName,
            "AssumeRolePolicyDocument": assumeRolePolicyDocument,
        ]
        if let desc = description, !desc.isEmpty {
            params["Description"] = desc
        }
        _ = try await client.iamRequest(action: "CreateRole", params: params)
    }

    func deleteRole(roleName: String) async throws {
        // Detach all policies first
        let attached = try await listAttachedRolePolicies(roleName: roleName)
        for policy in attached {
            try await detachRolePolicy(roleName: roleName, policyArn: policy.policyArn)
        }
        _ = try await client.iamRequest(
            action: "DeleteRole",
            params: ["RoleName": roleName]
        )
    }

    func listAttachedRolePolicies(roleName: String) async throws -> [IAMAttachedPolicy] {
        var allPolicies: [IAMAttachedPolicy] = []
        var marker: String? = nil

        repeat {
            var params: [String: String] = ["RoleName": roleName]
            if let m = marker {
                params["Marker"] = m
            }
            let data = try await client.iamRequest(action: "ListAttachedRolePolicies", params: params)
            let xml = try SNSXMLParser.parse(data)

            for member in xml.memberDicts {
                allPolicies.append(IAMAttachedPolicy(from: member))
            }
            if xml.first("IsTruncated") == "true" {
                marker = xml.first("Marker")
            } else {
                marker = nil
            }
            if allPolicies.count >= 10_000 { break }
        } while marker != nil

        return allPolicies
    }

    func attachRolePolicy(roleName: String, policyArn: String) async throws {
        _ = try await client.iamRequest(
            action: "AttachRolePolicy",
            params: ["RoleName": roleName, "PolicyArn": policyArn]
        )
    }

    func detachRolePolicy(roleName: String, policyArn: String) async throws {
        _ = try await client.iamRequest(
            action: "DetachRolePolicy",
            params: ["RoleName": roleName, "PolicyArn": policyArn]
        )
    }

    // MARK: - Policies

    func listPoliciesPage(scope: String = "Local", token: String? = nil) async throws -> ([IAMPolicy], String?) {
        var params: [String: String] = ["Scope": scope]
        if let token {
            params["Marker"] = token
        }
        let data = try await client.iamRequest(action: "ListPolicies", params: params)
        let xml = try SNSXMLParser.parse(data)
        let policies = xml.memberDicts.map { IAMPolicy(from: $0) }
        let next = xml.first("IsTruncated") == "true" ? xml.first("Marker") : nil
        return (policies, next)
    }

    func listPolicies(scope: String = "Local") async throws -> [IAMPolicy] {
        var allPolicies: [IAMPolicy] = []
        var marker: String? = nil
        repeat {
            let (policies, token) = try await listPoliciesPage(scope: scope, token: marker)
            allPolicies.append(contentsOf: policies)
            marker = token
            if allPolicies.count >= 10_000 { break }
        } while marker != nil
        return allPolicies
    }

    func createPolicy(policyName: String, policyDocument: String, description: String?) async throws {
        var params: [String: String] = [
            "PolicyName": policyName,
            "PolicyDocument": policyDocument,
        ]
        if let desc = description, !desc.isEmpty {
            params["Description"] = desc
        }
        _ = try await client.iamRequest(action: "CreatePolicy", params: params)
    }

    func deletePolicy(policyArn: String) async throws {
        // Delete all non-default policy versions first
        let versions = try await listPolicyVersions(policyArn: policyArn)
        for version in versions where !version.isDefault {
            _ = try await client.iamRequest(
                action: "DeletePolicyVersion",
                params: ["PolicyArn": policyArn, "VersionId": version.versionId]
            )
        }
        _ = try await client.iamRequest(
            action: "DeletePolicy",
            params: ["PolicyArn": policyArn]
        )
    }

    func getPolicyVersion(policyArn: String, versionId: String) async throws -> String {
        let data = try await client.iamRequest(
            action: "GetPolicyVersion",
            params: ["PolicyArn": policyArn, "VersionId": versionId]
        )
        let xml = try SNSXMLParser.parse(data)
        let encoded = xml.first("Document") ?? ""
        return encoded.removingPercentEncoding ?? encoded
    }

    struct PolicyVersionInfo: Hashable {
        let versionId: String
        let isDefault: Bool
    }

    func listPolicyVersions(policyArn: String) async throws -> [PolicyVersionInfo] {
        let data = try await client.iamRequest(
            action: "ListPolicyVersions",
            params: ["PolicyArn": policyArn]
        )
        let xml = try SNSXMLParser.parse(data)
        return xml.memberDicts.map { dict in
            PolicyVersionInfo(
                versionId: dict["VersionId"] ?? "",
                isDefault: dict["IsDefaultVersion"] == "true"
            )
        }
    }
}
