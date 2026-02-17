import Foundation

final class Route53Service: LocalStackService {
    // MARK: - Hosted Zone Operations

    func listHostedZones() async throws -> [Route53HostedZone] {
        var allZones: [Route53HostedZone] = []
        var nextMarker: String?

        repeat {
            var path = "/hostedzone"
            if let marker = nextMarker {
                path += "?marker=\(marker)"
            }
            let data = try await client.route53Request(method: "GET", path: path)
            let parser = Route53HostedZoneListParser()
            let result = try parser.parse(data: data)
            allZones.append(contentsOf: result.zones)
            nextMarker = result.isTruncated ? result.nextMarker : nil
        } while nextMarker != nil

        return allZones
    }

    func createHostedZone(name: String, comment: String) async throws -> String {
        let callerReference = UUID().uuidString
        let xml = """
            <CreateHostedZoneRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
                <Name>\(escapeXML(name))</Name>
                <CallerReference>\(escapeXML(callerReference))</CallerReference>
                <HostedZoneConfig>
                    <Comment>\(escapeXML(comment))</Comment>
                </HostedZoneConfig>
            </CreateHostedZoneRequest>
            """
        let body = xml.data(using: .utf8)!
        let data = try await client.route53Request(method: "POST", path: "/hostedzone", body: body)
        let parser = Route53CreateZoneResponseParser()
        return try parser.parse(data: data)
    }

    func deleteHostedZone(id: String) async throws {
        _ = try await client.route53Request(method: "DELETE", path: "/hostedzone/\(id)")
    }

    // MARK: - Record Set Operations

    func listResourceRecordSets(zoneId: String) async throws -> [Route53RecordSet] {
        var allRecords: [Route53RecordSet] = []
        var nextName: String?
        var nextType: String?

        repeat {
            var path = "/hostedzone/\(zoneId)/rrset"
            var queryParts: [String] = []
            if let name = nextName {
                queryParts.append("name=\(name)")
            }
            if let type = nextType {
                queryParts.append("type=\(type)")
            }
            if !queryParts.isEmpty {
                path += "?" + queryParts.joined(separator: "&")
            }
            let data = try await client.route53Request(method: "GET", path: path)
            let parser = Route53RecordSetListParser()
            let result = try parser.parse(data: data)
            allRecords.append(contentsOf: result.recordSets)
            if result.isTruncated {
                nextName = result.nextRecordName
                nextType = result.nextRecordType
            } else {
                nextName = nil
                nextType = nil
            }
        } while nextName != nil

        return allRecords
    }

    func createRecordSet(zoneId: String, name: String, type: String, ttl: Int, values: [String]) async throws {
        let valuesXML = values.map { "                        <ResourceRecord><Value>\(escapeXML($0))</Value></ResourceRecord>" }.joined(separator: "\n")
        let xml = """
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
                <ChangeBatch>
                    <Changes>
                        <Change>
                            <Action>CREATE</Action>
                            <ResourceRecordSet>
                                <Name>\(escapeXML(name))</Name>
                                <Type>\(escapeXML(type))</Type>
                                <TTL>\(ttl)</TTL>
                                <ResourceRecords>
            \(valuesXML)
                                </ResourceRecords>
                            </ResourceRecordSet>
                        </Change>
                    </Changes>
                </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
            """
        let body = xml.data(using: .utf8)!
        _ = try await client.route53Request(method: "POST", path: "/hostedzone/\(zoneId)/rrset", body: body)
    }

    func deleteRecordSet(zoneId: String, recordSet: Route53RecordSet) async throws {
        guard !recordSet.isAlias else { return }
        let valuesXML = recordSet.values.map { "                        <ResourceRecord><Value>\(escapeXML($0))</Value></ResourceRecord>" }.joined(separator: "\n")
        let xml = """
            <ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
                <ChangeBatch>
                    <Changes>
                        <Change>
                            <Action>DELETE</Action>
                            <ResourceRecordSet>
                                <Name>\(escapeXML(recordSet.name))</Name>
                                <Type>\(escapeXML(recordSet.type))</Type>
                                <TTL>\(recordSet.ttl ?? 300)</TTL>
                                <ResourceRecords>
            \(valuesXML)
                                </ResourceRecords>
                            </ResourceRecordSet>
                        </Change>
                    </Changes>
                </ChangeBatch>
            </ChangeResourceRecordSetsRequest>
            """
        let body = xml.data(using: .utf8)!
        _ = try await client.route53Request(method: "POST", path: "/hostedzone/\(zoneId)/rrset", body: body)
    }

    // MARK: - Helpers

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
