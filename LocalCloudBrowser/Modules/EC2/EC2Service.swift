import Foundation

final class EC2Service: BaseService {
    // MARK: - Instances

    func listInstances(region: String? = nil) async throws -> [EC2Instance] {
        let data = try await client.ec2Request(action: "DescribeInstances", region: region)
        let root = try EC2XMLParser.parse(data)
        var instances: [EC2Instance] = []
        for reservation in root.child("reservationSet")?.all("item") ?? [] {
            for item in reservation.child("instancesSet")?.all("item") ?? [] {
                instances.append(EC2Instance(from: item))
            }
        }
        return instances
    }

    func runInstance(
        imageId: String,
        instanceType: String,
        keyName: String?,
        securityGroupIds: [String],
        count: Int
    ) async throws {
        var params: [String: String] = [
            "ImageId": imageId,
            "InstanceType": instanceType,
            "MinCount": "\(count)",
            "MaxCount": "\(count)",
        ]
        if let key = keyName, !key.isEmpty {
            params["KeyName"] = key
        }
        for (i, sgId) in securityGroupIds.enumerated() {
            params["SecurityGroupId.\(i + 1)"] = sgId
        }
        _ = try await client.ec2Request(action: "RunInstances", params: params)
    }

    func startInstances(_ instanceIds: [String]) async throws {
        var params: [String: String] = [:]
        for (i, id) in instanceIds.enumerated() {
            params["InstanceId.\(i + 1)"] = id
        }
        _ = try await client.ec2Request(action: "StartInstances", params: params)
    }

    func stopInstances(_ instanceIds: [String]) async throws {
        var params: [String: String] = [:]
        for (i, id) in instanceIds.enumerated() {
            params["InstanceId.\(i + 1)"] = id
        }
        _ = try await client.ec2Request(action: "StopInstances", params: params)
    }

    func terminateInstances(_ instanceIds: [String]) async throws {
        var params: [String: String] = [:]
        for (i, id) in instanceIds.enumerated() {
            params["InstanceId.\(i + 1)"] = id
        }
        _ = try await client.ec2Request(action: "TerminateInstances", params: params)
    }

    func rebootInstances(_ instanceIds: [String]) async throws {
        var params: [String: String] = [:]
        for (i, id) in instanceIds.enumerated() {
            params["InstanceId.\(i + 1)"] = id
        }
        _ = try await client.ec2Request(action: "RebootInstances", params: params)
    }

    // MARK: - Security Groups

    func listSecurityGroups() async throws -> [EC2SecurityGroup] {
        let data = try await client.ec2Request(action: "DescribeSecurityGroups")
        let root = try EC2XMLParser.parse(data)
        return (root.child("securityGroupInfo")?.all("item") ?? []).map {
            EC2SecurityGroup(from: $0)
        }
    }

    func createSecurityGroup(name: String, description: String, vpcId: String?) async throws -> String {
        var params: [String: String] = [
            "GroupName": name,
            "GroupDescription": description,
        ]
        if let vpc = vpcId, !vpc.isEmpty {
            params["VpcId"] = vpc
        }
        let data = try await client.ec2Request(action: "CreateSecurityGroup", params: params)
        let root = try EC2XMLParser.parse(data)
        return root["groupId"]
    }

    func deleteSecurityGroup(groupId: String) async throws {
        _ = try await client.ec2Request(
            action: "DeleteSecurityGroup",
            params: ["GroupId": groupId]
        )
    }

    func authorizeSecurityGroupIngress(
        groupId: String,
        ipProtocol: String,
        fromPort: Int?,
        toPort: Int?,
        cidrIp: String,
        description: String?
    ) async throws {
        var params: [String: String] = [
            "GroupId": groupId,
            "IpPermissions.1.IpProtocol": ipProtocol,
            "IpPermissions.1.IpRanges.1.CidrIp": cidrIp,
        ]
        if let from = fromPort {
            params["IpPermissions.1.FromPort"] = "\(from)"
        }
        if let to = toPort {
            params["IpPermissions.1.ToPort"] = "\(to)"
        }
        if let desc = description, !desc.isEmpty {
            params["IpPermissions.1.IpRanges.1.Description"] = desc
        }
        _ = try await client.ec2Request(action: "AuthorizeSecurityGroupIngress", params: params)
    }

    func revokeSecurityGroupIngress(
        groupId: String,
        ipProtocol: String,
        fromPort: Int?,
        toPort: Int?,
        cidrIp: String
    ) async throws {
        var params: [String: String] = [
            "GroupId": groupId,
            "IpPermissions.1.IpProtocol": ipProtocol,
            "IpPermissions.1.IpRanges.1.CidrIp": cidrIp,
        ]
        if let from = fromPort {
            params["IpPermissions.1.FromPort"] = "\(from)"
        }
        if let to = toPort {
            params["IpPermissions.1.ToPort"] = "\(to)"
        }
        _ = try await client.ec2Request(action: "RevokeSecurityGroupIngress", params: params)
    }

    func authorizeSecurityGroupEgress(
        groupId: String,
        ipProtocol: String,
        fromPort: Int?,
        toPort: Int?,
        cidrIp: String,
        description: String?
    ) async throws {
        var params: [String: String] = [
            "GroupId": groupId,
            "IpPermissions.1.IpProtocol": ipProtocol,
            "IpPermissions.1.IpRanges.1.CidrIp": cidrIp,
        ]
        if let from = fromPort {
            params["IpPermissions.1.FromPort"] = "\(from)"
        }
        if let to = toPort {
            params["IpPermissions.1.ToPort"] = "\(to)"
        }
        if let desc = description, !desc.isEmpty {
            params["IpPermissions.1.IpRanges.1.Description"] = desc
        }
        _ = try await client.ec2Request(action: "AuthorizeSecurityGroupEgress", params: params)
    }

    func revokeSecurityGroupEgress(
        groupId: String,
        ipProtocol: String,
        fromPort: Int?,
        toPort: Int?,
        cidrIp: String
    ) async throws {
        var params: [String: String] = [
            "GroupId": groupId,
            "IpPermissions.1.IpProtocol": ipProtocol,
            "IpPermissions.1.IpRanges.1.CidrIp": cidrIp,
        ]
        if let from = fromPort {
            params["IpPermissions.1.FromPort"] = "\(from)"
        }
        if let to = toPort {
            params["IpPermissions.1.ToPort"] = "\(to)"
        }
        _ = try await client.ec2Request(action: "RevokeSecurityGroupEgress", params: params)
    }

    // MARK: - Key Pairs

    func listKeyPairs() async throws -> [EC2KeyPair] {
        let data = try await client.ec2Request(action: "DescribeKeyPairs")
        let root = try EC2XMLParser.parse(data)
        return (root.child("keySet")?.all("item") ?? []).map {
            EC2KeyPair(from: $0)
        }
    }

    func createKeyPair(keyName: String) async throws -> EC2CreatedKeyPair {
        let data = try await client.ec2Request(
            action: "CreateKeyPair",
            params: ["KeyName": keyName]
        )
        let root = try EC2XMLParser.parse(data)
        return EC2CreatedKeyPair(
            keyName: root["keyName"],
            keyPairId: root["keyPairId"],
            keyFingerprint: root["keyFingerprint"],
            keyMaterial: root["keyMaterial"]
        )
    }

    func deleteKeyPair(keyName: String) async throws {
        _ = try await client.ec2Request(
            action: "DeleteKeyPair",
            params: ["KeyName": keyName]
        )
    }
}
