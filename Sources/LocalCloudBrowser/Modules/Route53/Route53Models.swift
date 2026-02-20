import Foundation
import SwiftUI

struct Route53HostedZone: Identifiable, Hashable {
    let id: String
    let name: String
    let callerReference: String
    let comment: String
    let privateZone: Bool
    let recordSetCount: Int

    var displayName: String {
        // Remove trailing dot from DNS names
        if name.hasSuffix(".") {
            return String(name.dropLast())
        }
        return name
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func listRecordSetsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53 list-resource-record-sets \\",
            "  --hosted-zone-id '\(Self.shellEscape(id))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func deleteZoneCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53 delete-hosted-zone \\",
            "  --id '\(Self.shellEscape(id))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listZonesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws route53 list-hosted-zones \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct Route53RecordSet: Identifiable, Hashable {
    let name: String
    let type: String
    let ttl: Int?
    let values: [String]
    let aliasTarget: Route53AliasTarget?
    let weight: Int?
    let setIdentifier: String?

    var id: String { "\(name)|\(type)|\(setIdentifier ?? "")" }

    var displayName: String {
        if name.hasSuffix(".") {
            return String(name.dropLast())
        }
        return name
    }

    var valuesPreview: String {
        if let alias = aliasTarget {
            return "ALIAS \(alias.dnsName)"
        }
        return values.joined(separator: ", ")
    }

    var isAlias: Bool { aliasTarget != nil }

    var typeBadgeColor: Color {
        switch type {
        case "A", "AAAA": .blue
        case "CNAME": .purple
        case "MX": .orange
        case "NS": .green
        case "SOA": .gray
        case "TXT": .teal
        case "SRV": .indigo
        case "PTR": .cyan
        case "CAA": .brown
        default: .secondary
        }
    }
}

struct Route53AliasTarget: Hashable {
    let hostedZoneId: String
    let dnsName: String
}

/// All standard DNS record types supported by Route 53.
let route53RecordTypes = [
    "A", "AAAA", "CNAME", "MX", "NS", "TXT", "SRV", "PTR", "CAA", "SOA",
]
