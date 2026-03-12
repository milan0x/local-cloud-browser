import Foundation
import SwiftUI

// MARK: - Entity Type

enum EC2EntityType: String, CaseIterable {
    case instances = "Instances"
    case securityGroups = "Security Groups"
    case keyPairs = "Key Pairs"
}

// MARK: - Instance

enum EC2InstanceState: String {
    case pending
    case running
    case shuttingDown = "shutting-down"
    case terminated
    case stopping
    case stopped

    var color: Color {
        switch self {
        case .pending: .yellow
        case .running: .green
        case .shuttingDown: .orange
        case .terminated: .gray
        case .stopping: .orange
        case .stopped: .red
        }
    }

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .shuttingDown: "Shutting Down"
        case .terminated: "Terminated"
        case .stopping: "Stopping"
        case .stopped: "Stopped"
        }
    }

    var canStart: Bool { self == .stopped }
    var canStop: Bool { self == .running }
    var canTerminate: Bool { self != .terminated && self != .shuttingDown }
    var canReboot: Bool { self == .running }
}

struct EC2InstanceSecurityGroup: Identifiable, Hashable {
    let groupId: String
    let groupName: String

    var id: String { groupId }

    init(from node: EC2XMLNode) {
        groupId = node["groupId"]
        groupName = node["groupName"]
    }
}

struct EC2Instance: Identifiable, Hashable {
    let instanceId: String
    let imageId: String
    let instanceType: String
    let state: EC2InstanceState
    let stateCode: Int
    let privateIpAddress: String?
    let publicIpAddress: String?
    let keyName: String?
    let availabilityZone: String?
    let launchTime: Date?
    let nameTag: String?
    let securityGroups: [EC2InstanceSecurityGroup]

    var id: String { instanceId }

    var displayName: String {
        if let name = nameTag, !name.isEmpty {
            return name
        }
        return instanceId
    }

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        return iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeInstanceCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ec2 describe-instances \\",
            "  --instance-ids '\(Self.shellEscape(instanceId))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from node: EC2XMLNode) {
        instanceId = node["instanceId"]
        imageId = node["imageId"]
        instanceType = node["instanceType"]
        let stateName = node.child("instanceState")?["name"] ?? ""
        state = EC2InstanceState(rawValue: stateName) ?? .pending
        stateCode = Int(node.child("instanceState")?["code"] ?? "0") ?? 0
        let privIp = node["privateIpAddress"]
        privateIpAddress = privIp.isEmpty ? nil : privIp
        let pubIp = node["ipAddress"]
        publicIpAddress = pubIp.isEmpty ? nil : pubIp
        let key = node["keyName"]
        keyName = key.isEmpty ? nil : key
        let az = node.child("placement")?["availabilityZone"] ?? ""
        availabilityZone = az.isEmpty ? nil : az
        launchTime = Self.parseDate(node["launchTime"])

        // Parse Name tag
        var name: String?
        for tagItem in node.child("tagSet")?.all("item") ?? [] {
            if tagItem["key"] == "Name" {
                name = tagItem["value"]
                break
            }
        }
        nameTag = name

        securityGroups = (node.child("groupSet")?.all("item") ?? []).map {
            EC2InstanceSecurityGroup(from: $0)
        }
    }
}

// MARK: - Security Group

struct EC2SecurityGroupRule: Identifiable, Hashable {
    let ipProtocol: String
    let fromPort: Int?
    let toPort: Int?
    let cidrIp: String
    let description: String?

    var id: String { "\(ipProtocol):\(fromPort ?? -1):\(toPort ?? -1):\(cidrIp)" }

    var protocolDisplay: String {
        if ipProtocol == "-1" { return "All traffic" }
        return ipProtocol.uppercased()
    }

    var portRangeDisplay: String {
        if ipProtocol == "-1" { return "All" }
        if ipProtocol.lowercased() == "icmp" { return "N/A" }
        guard let from = fromPort, let to = toPort else { return "All" }
        if from == to { return "\(from)" }
        return "\(from)-\(to)"
    }

    init(from node: EC2XMLNode) {
        ipProtocol = node["ipProtocol"]
        let from = node["fromPort"]
        fromPort = from.isEmpty ? nil : Int(from)
        let to = node["toPort"]
        toPort = to.isEmpty ? nil : Int(to)

        // Get first CIDR from ipRanges
        let firstRange = node.child("ipRanges")?.child("item")
        cidrIp = firstRange?["cidrIp"] ?? ""
        let desc = firstRange?["description"] ?? ""
        description = desc.isEmpty ? nil : desc
    }

    init(ipProtocol: String, fromPort: Int?, toPort: Int?, cidrIp: String, description: String?) {
        self.ipProtocol = ipProtocol
        self.fromPort = fromPort
        self.toPort = toPort
        self.cidrIp = cidrIp
        self.description = description
    }
}

struct EC2SecurityGroup: Identifiable, Hashable {
    let groupId: String
    let groupName: String
    let groupDescription: String
    let vpcId: String?
    let inboundRules: [EC2SecurityGroupRule]
    let outboundRules: [EC2SecurityGroupRule]

    var id: String { groupId }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeGroupCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ec2 describe-security-groups \\",
            "  --group-ids '\(Self.shellEscape(groupId))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from node: EC2XMLNode) {
        groupId = node["groupId"]
        groupName = node["groupName"]
        groupDescription = node["groupDescription"]
        let vpc = node["vpcId"]
        vpcId = vpc.isEmpty ? nil : vpc

        inboundRules = (node.child("ipPermissions")?.all("item") ?? []).map {
            EC2SecurityGroupRule(from: $0)
        }
        outboundRules = (node.child("ipPermissionsEgress")?.all("item") ?? []).map {
            EC2SecurityGroupRule(from: $0)
        }
    }
}

// MARK: - Key Pair

struct EC2KeyPair: Identifiable, Hashable {
    let keyName: String
    let keyPairId: String
    let keyFingerprint: String

    var id: String { keyName }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeKeyPairCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ec2 describe-key-pairs \\",
            "  --key-names '\(Self.shellEscape(keyName))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from node: EC2XMLNode) {
        keyName = node["keyName"]
        keyPairId = node["keyPairId"]
        keyFingerprint = node["keyFingerprint"]
    }
}

struct EC2CreatedKeyPair {
    let keyName: String
    let keyPairId: String
    let keyFingerprint: String
    let keyMaterial: String
}

// MARK: - XML Tree Parser

final class EC2XMLNode {
    let name: String
    var text: String = ""
    var children: [EC2XMLNode] = []

    init(name: String) {
        self.name = name
    }

    func child(_ name: String) -> EC2XMLNode? {
        children.first { $0.name == name }
    }

    func all(_ name: String) -> [EC2XMLNode] {
        children.filter { $0.name == name }
    }

    subscript(_ name: String) -> String {
        child(name)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class EC2XMLParser: NSObject, XMLParserDelegate {
    private var nodeStack: [EC2XMLNode] = []
    private(set) var root: EC2XMLNode?

    static func parse(_ data: Data) throws -> EC2XMLNode {
        let p = EC2XMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse(), let root = p.root else {
            throw SNSXMLParseError.parseFailure(
                parser.parserError?.localizedDescription ?? "Unknown EC2 XML parse error"
            )
        }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let node = EC2XMLNode(name: elementName)
        if let parent = nodeStack.last {
            parent.children.append(node)
        }
        nodeStack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        nodeStack.last?.text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let finished = nodeStack.removeLast()
        if nodeStack.isEmpty {
            root = finished
        }
    }
}
