import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Route 53 Models")
struct Route53ModelTests {

    // MARK: - Route53HostedZone.displayName

    @Test("displayName strips trailing dot")
    func displayNameTrailingDot() {
        let zone = Route53HostedZone(
            id: "Z1", name: "example.com.", callerReference: "ref",
            comment: "", privateZone: false, recordSetCount: 2
        )
        #expect(zone.displayName == "example.com")
    }

    @Test("displayName keeps name without trailing dot")
    func displayNameNoDot() {
        let zone = Route53HostedZone(
            id: "Z1", name: "example.com", callerReference: "ref",
            comment: "", privateZone: false, recordSetCount: 0
        )
        #expect(zone.displayName == "example.com")
    }

    // MARK: - Route53RecordSet

    @Test("displayName strips trailing dot")
    func recordSetDisplayName() {
        let rs = Route53RecordSet(
            name: "www.example.com.", type: "A", ttl: 300,
            values: ["1.2.3.4"], aliasTarget: nil, weight: nil, setIdentifier: nil
        )
        #expect(rs.displayName == "www.example.com")
    }

    @Test("valuesPreview shows values")
    func recordSetValuesPreview() {
        let rs = Route53RecordSet(
            name: "example.com.", type: "A", ttl: 300,
            values: ["1.2.3.4", "5.6.7.8"], aliasTarget: nil, weight: nil, setIdentifier: nil
        )
        #expect(rs.valuesPreview == "1.2.3.4, 5.6.7.8")
    }

    @Test("valuesPreview shows ALIAS for alias records")
    func recordSetValuesPreviewAlias() {
        let rs = Route53RecordSet(
            name: "example.com.", type: "A", ttl: nil,
            values: [],
            aliasTarget: Route53AliasTarget(hostedZoneId: "Z1", dnsName: "elb.amazonaws.com"),
            weight: nil, setIdentifier: nil
        )
        #expect(rs.valuesPreview.contains("ALIAS"))
        #expect(rs.valuesPreview.contains("elb.amazonaws.com"))
    }

    @Test("isAlias returns true for alias records")
    func isAlias() {
        let alias = Route53RecordSet(
            name: "x", type: "A", ttl: nil, values: [],
            aliasTarget: Route53AliasTarget(hostedZoneId: "Z", dnsName: "d"),
            weight: nil, setIdentifier: nil
        )
        #expect(alias.isAlias == true)

        let normal = Route53RecordSet(
            name: "x", type: "A", ttl: 300, values: ["1.2.3.4"],
            aliasTarget: nil, weight: nil, setIdentifier: nil
        )
        #expect(normal.isAlias == false)
    }

    // MARK: - normalizeZoneId

    @Test("normalizeZoneId strips /hostedzone/ prefix")
    func normalizeWithPrefix() {
        #expect(normalizeZoneId("/hostedzone/Z12345") == "Z12345")
    }

    @Test("normalizeZoneId returns ID without prefix as-is")
    func normalizeWithoutPrefix() {
        #expect(normalizeZoneId("Z12345") == "Z12345")
    }

    // MARK: - CLI

    @Test("listRecordSetsCLI generates valid command")
    func listRecordSetsCLI() {
        let zone = Route53HostedZone(
            id: "Z12345", name: "example.com.", callerReference: "ref",
            comment: "", privateZone: false, recordSetCount: 2
        )
        let cli = zone.listRecordSetsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws route53 list-resource-record-sets"))
        #expect(cli.contains("Z12345"))
    }

    @Test("listZonesCLI generates valid command")
    func listZonesCLI() {
        let cli = Route53HostedZone.listZonesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws route53 list-hosted-zones"))
    }
}
