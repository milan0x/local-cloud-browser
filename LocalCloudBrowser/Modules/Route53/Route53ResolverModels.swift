import Foundation
import SwiftUI

enum Route53Tab: String, CaseIterable {
    case zones = "Zones"
    case resolver = "Resolver"
}

struct ResolverEndpoint: Identifiable, Hashable {
    let id: String
    let name: String
    let arn: String
    let direction: String
    let status: String
    let statusMessage: String
    let ipAddressCount: Int
    let hostVPCId: String
    let creationTime: String
    let modificationTime: String

    var statusBadgeColor: Color {
        switch status {
        case "OPERATIONAL": .green
        case "CREATING", "UPDATING": .orange
        case "DELETING": .red
        case "ACTION_NEEDED": .yellow
        case "AUTO_RECOVERING": .blue
        default: .gray
        }
    }

    var directionBadgeColor: Color {
        switch direction {
        case "INBOUND": .blue
        case "OUTBOUND": .purple
        default: .gray
        }
    }

    init(from dict: [String: Any]) {
        id = dict["Id"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String ?? ""
        direction = dict["Direction"] as? String ?? ""
        status = dict["Status"] as? String ?? ""
        statusMessage = dict["StatusMessage"] as? String ?? ""
        ipAddressCount = dict["IpAddressCount"] as? Int ?? 0
        hostVPCId = dict["HostVPCId"] as? String ?? ""
        creationTime = dict["CreationTime"] as? String ?? ""
        modificationTime = dict["ModificationTime"] as? String ?? ""
    }

    func describeCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver get-resolver-endpoint \\",
            "  --resolver-endpoint-id '\(id.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func deleteCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver delete-resolver-endpoint \\",
            "  --resolver-endpoint-id '\(id.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver list-resolver-endpoints \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct ResolverIpAddress: Identifiable {
    let ipId: String
    let subnetId: String
    let ip: String
    let status: String
    let statusMessage: String

    var id: String { ipId }

    init(from dict: [String: Any]) {
        ipId = dict["IpId"] as? String ?? ""
        subnetId = dict["SubnetId"] as? String ?? ""
        ip = dict["Ip"] as? String ?? ""
        status = dict["Status"] as? String ?? ""
        statusMessage = dict["StatusMessage"] as? String ?? ""
    }
}

struct ResolverRule: Identifiable, Hashable {
    let id: String
    let name: String
    let arn: String
    let status: String
    let statusMessage: String
    let ruleType: String
    let domainName: String
    let targetIps: [ResolverRuleTargetIp]
    let resolverEndpointId: String?
    let creationTime: String
    let modificationTime: String

    var statusBadgeColor: Color {
        switch status {
        case "COMPLETE": .green
        case "DELETING", "FAILED": .red
        case "UPDATING": .orange
        default: .gray
        }
    }

    var ruleTypeBadgeColor: Color {
        switch ruleType {
        case "FORWARD": .blue
        case "SYSTEM": .gray
        case "RECURSIVE": .purple
        default: .gray
        }
    }

    init(from dict: [String: Any]) {
        id = dict["Id"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String ?? ""
        status = dict["Status"] as? String ?? ""
        statusMessage = dict["StatusMessage"] as? String ?? ""
        ruleType = dict["RuleType"] as? String ?? ""
        domainName = dict["DomainName"] as? String ?? ""
        resolverEndpointId = dict["ResolverEndpointId"] as? String
        creationTime = dict["CreationTime"] as? String ?? ""
        modificationTime = dict["ModificationTime"] as? String ?? ""
        if let ips = dict["TargetIps"] as? [[String: Any]] {
            targetIps = ips.map { ResolverRuleTargetIp(from: $0) }
        } else {
            targetIps = []
        }
    }

    func describeCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver get-resolver-rule \\",
            "  --resolver-rule-id '\(id.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func deleteCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver delete-resolver-rule \\",
            "  --resolver-rule-id '\(id.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53resolver list-resolver-rules \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct ResolverRuleTargetIp: Hashable {
    let ip: String
    let port: Int

    init(from dict: [String: Any]) {
        ip = dict["Ip"] as? String ?? ""
        port = dict["Port"] as? Int ?? 53
    }
}

struct ResolverRuleAssociation: Identifiable, Hashable {
    let id: String
    let resolverRuleId: String
    let name: String
    let vpcId: String
    let status: String
    let statusMessage: String

    init(from dict: [String: Any]) {
        id = dict["Id"] as? String ?? ""
        resolverRuleId = dict["ResolverRuleId"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        vpcId = dict["VPCId"] as? String ?? ""
        status = dict["Status"] as? String ?? ""
        statusMessage = dict["StatusMessage"] as? String ?? ""
    }
}
