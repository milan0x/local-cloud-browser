import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("Route 53 XML Parser")
struct Route53XMLParserTests {

    // MARK: - Hosted Zone List Parser

    @Test("parses hosted zones from XML")
    func parseHostedZones() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListHostedZonesResponse>
            <HostedZones>
                <HostedZone>
                    <Id>/hostedzone/Z12345</Id>
                    <Name>example.com.</Name>
                    <CallerReference>ref-1</CallerReference>
                    <Config>
                        <Comment>My zone</Comment>
                        <PrivateZone>false</PrivateZone>
                    </Config>
                    <ResourceRecordSetCount>4</ResourceRecordSetCount>
                </HostedZone>
                <HostedZone>
                    <Id>/hostedzone/Z67890</Id>
                    <Name>internal.local.</Name>
                    <CallerReference>ref-2</CallerReference>
                    <Config>
                        <PrivateZone>true</PrivateZone>
                    </Config>
                    <ResourceRecordSetCount>2</ResourceRecordSetCount>
                </HostedZone>
            </HostedZones>
            <IsTruncated>false</IsTruncated>
        </ListHostedZonesResponse>
        """
        let data = xml.data(using: .utf8)!
        let parser = Route53HostedZoneListParser()
        let result = try parser.parse(data: data)

        #expect(result.zones.count == 2)
        #expect(result.zones[0].id == "Z12345")
        #expect(result.zones[0].name == "example.com.")
        #expect(result.zones[0].comment == "My zone")
        #expect(result.zones[0].privateZone == false)
        #expect(result.zones[0].recordSetCount == 4)

        #expect(result.zones[1].id == "Z67890")
        #expect(result.zones[1].privateZone == true)
        #expect(result.isTruncated == false)
    }

    @Test("parses truncated response with marker")
    func parseTruncated() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListHostedZonesResponse>
            <HostedZones>
                <HostedZone>
                    <Id>/hostedzone/Z1</Id>
                    <Name>test.com.</Name>
                    <CallerReference>ref</CallerReference>
                    <Config><PrivateZone>false</PrivateZone></Config>
                    <ResourceRecordSetCount>1</ResourceRecordSetCount>
                </HostedZone>
            </HostedZones>
            <IsTruncated>true</IsTruncated>
            <NextMarker>Z1</NextMarker>
        </ListHostedZonesResponse>
        """
        let data = xml.data(using: .utf8)!
        let parser = Route53HostedZoneListParser()
        let result = try parser.parse(data: data)

        #expect(result.isTruncated == true)
        #expect(result.nextMarker == "Z1")
    }

    // MARK: - Record Set List Parser

    @Test("parses record sets from XML")
    func parseRecordSets() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListResourceRecordSetsResponse>
            <ResourceRecordSets>
                <ResourceRecordSet>
                    <Name>example.com.</Name>
                    <Type>A</Type>
                    <TTL>300</TTL>
                    <ResourceRecords>
                        <ResourceRecord><Value>1.2.3.4</Value></ResourceRecord>
                        <ResourceRecord><Value>5.6.7.8</Value></ResourceRecord>
                    </ResourceRecords>
                </ResourceRecordSet>
                <ResourceRecordSet>
                    <Name>www.example.com.</Name>
                    <Type>CNAME</Type>
                    <AliasTarget>
                        <HostedZoneId>Z1</HostedZoneId>
                        <DNSName>elb.amazonaws.com</DNSName>
                    </AliasTarget>
                </ResourceRecordSet>
            </ResourceRecordSets>
            <IsTruncated>false</IsTruncated>
        </ListResourceRecordSetsResponse>
        """
        let data = xml.data(using: .utf8)!
        let parser = Route53RecordSetListParser()
        let result = try parser.parse(data: data)

        #expect(result.recordSets.count == 2)

        let aRecord = result.recordSets[0]
        #expect(aRecord.name == "example.com.")
        #expect(aRecord.type == "A")
        #expect(aRecord.ttl == 300)
        #expect(aRecord.values == ["1.2.3.4", "5.6.7.8"])
        #expect(aRecord.aliasTarget == nil)

        let cname = result.recordSets[1]
        #expect(cname.type == "CNAME")
        #expect(cname.aliasTarget?.dnsName == "elb.amazonaws.com")
        #expect(cname.aliasTarget?.hostedZoneId == "Z1")
    }

    @Test("parses weighted record set with SetIdentifier")
    func parseWeightedRecordSet() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ListResourceRecordSetsResponse>
            <ResourceRecordSets>
                <ResourceRecordSet>
                    <Name>api.example.com.</Name>
                    <Type>A</Type>
                    <TTL>60</TTL>
                    <Weight>70</Weight>
                    <SetIdentifier>primary</SetIdentifier>
                    <ResourceRecords>
                        <ResourceRecord><Value>10.0.0.1</Value></ResourceRecord>
                    </ResourceRecords>
                </ResourceRecordSet>
            </ResourceRecordSets>
            <IsTruncated>false</IsTruncated>
        </ListResourceRecordSetsResponse>
        """
        let data = xml.data(using: .utf8)!
        let parser = Route53RecordSetListParser()
        let result = try parser.parse(data: data)

        #expect(result.recordSets.count == 1)
        #expect(result.recordSets[0].weight == 70)
        #expect(result.recordSets[0].setIdentifier == "primary")
    }

    // MARK: - Create Zone Response Parser

    @Test("parses zone ID from create response")
    func parseCreateZoneResponse() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <CreateHostedZoneResponse>
            <HostedZone>
                <Id>/hostedzone/ZNEWZONE</Id>
                <Name>new.example.com.</Name>
                <CallerReference>unique-ref</CallerReference>
                <Config><PrivateZone>false</PrivateZone></Config>
            </HostedZone>
        </CreateHostedZoneResponse>
        """
        let data = xml.data(using: .utf8)!
        let parser = Route53CreateZoneResponseParser()
        let zoneId = try parser.parse(data: data)
        #expect(zoneId == "ZNEWZONE")
    }
}
