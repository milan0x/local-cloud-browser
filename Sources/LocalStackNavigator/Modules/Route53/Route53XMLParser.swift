import Foundation

enum Route53XMLParseError: Error, LocalizedError {
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let detail):
            "Failed to parse Route 53 XML response: \(detail)"
        }
    }
}

// MARK: - Hosted Zone List Parser

struct Route53HostedZoneParseResult {
    let zones: [Route53HostedZone]
    let isTruncated: Bool
    let nextMarker: String?
}

final class Route53HostedZoneListParser: NSObject, XMLParserDelegate {
    private var zones: [Route53HostedZone] = []
    private var currentElement = ""
    private var currentText = ""
    private var inHostedZone = false
    private var inConfig = false
    private var isTruncated = false
    private var nextMarker: String?

    private var zoneId = ""
    private var zoneName = ""
    private var callerReference = ""
    private var comment = ""
    private var privateZone = false
    private var recordSetCount = 0

    func parse(data: Data) throws -> Route53HostedZoneParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw Route53XMLParseError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return Route53HostedZoneParseResult(zones: zones, isTruncated: isTruncated, nextMarker: nextMarker)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "HostedZone" {
            inHostedZone = true
            zoneId = ""
            zoneName = ""
            callerReference = ""
            comment = ""
            privateZone = false
            recordSetCount = 0
        } else if elementName == "Config" {
            inConfig = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inHostedZone {
            if inConfig {
                switch elementName {
                case "Comment": comment = text
                case "PrivateZone": privateZone = text.lowercased() == "true"
                case "Config": inConfig = false
                default: break
                }
            } else {
                switch elementName {
                case "Id": zoneId = text
                case "Name": zoneName = text
                case "CallerReference": callerReference = text
                case "ResourceRecordSetCount": recordSetCount = Int(text) ?? 0
                case "HostedZone":
                    zones.append(Route53HostedZone(
                        id: normalizeZoneId(zoneId),
                        name: zoneName,
                        callerReference: callerReference,
                        comment: comment,
                        privateZone: privateZone,
                        recordSetCount: recordSetCount
                    ))
                    inHostedZone = false
                default: break
                }
            }
        } else {
            switch elementName {
            case "IsTruncated": isTruncated = text.lowercased() == "true"
            case "NextMarker": nextMarker = text
            default: break
            }
        }

        currentElement = ""
    }
}

// MARK: - Record Set List Parser

struct Route53RecordSetParseResult {
    let recordSets: [Route53RecordSet]
    let isTruncated: Bool
    let nextRecordName: String?
    let nextRecordType: String?
}

final class Route53RecordSetListParser: NSObject, XMLParserDelegate {
    private var recordSets: [Route53RecordSet] = []
    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []
    private var isTruncated = false
    private var nextRecordName: String?
    private var nextRecordType: String?

    // Current record set fields
    private var inRecordSet = false
    private var inResourceRecords = false
    private var inAliasTarget = false
    private var rsName = ""
    private var rsType = ""
    private var rsTTL: Int?
    private var rsValues: [String] = []
    private var rsAliasHostedZoneId = ""
    private var rsAliasDNSName = ""
    private var rsWeight: Int?
    private var rsSetIdentifier = ""

    func parse(data: Data) throws -> Route53RecordSetParseResult {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw Route53XMLParseError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return Route53RecordSetParseResult(
            recordSets: recordSets,
            isTruncated: isTruncated,
            nextRecordName: nextRecordName,
            nextRecordType: nextRecordType
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        elementStack.append(elementName)
        currentElement = elementName
        currentText = ""
        if elementName == "ResourceRecordSet" {
            inRecordSet = true
            rsName = ""
            rsType = ""
            rsTTL = nil
            rsValues = []
            rsAliasHostedZoneId = ""
            rsAliasDNSName = ""
            rsWeight = nil
            rsSetIdentifier = ""
        } else if elementName == "ResourceRecords" {
            inResourceRecords = true
        } else if elementName == "AliasTarget" {
            inAliasTarget = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inRecordSet {
            if inAliasTarget {
                switch elementName {
                case "HostedZoneId": rsAliasHostedZoneId = text
                case "DNSName": rsAliasDNSName = text
                case "AliasTarget": inAliasTarget = false
                default: break
                }
            } else if inResourceRecords {
                switch elementName {
                case "Value": rsValues.append(text)
                case "ResourceRecords": inResourceRecords = false
                default: break
                }
            } else {
                switch elementName {
                case "Name": rsName = text
                case "Type": rsType = text
                case "TTL": rsTTL = Int(text)
                case "Weight": rsWeight = Int(text)
                case "SetIdentifier": rsSetIdentifier = text
                case "ResourceRecordSet":
                    let aliasTarget: Route53AliasTarget? = rsAliasDNSName.isEmpty ? nil : Route53AliasTarget(
                        hostedZoneId: rsAliasHostedZoneId,
                        dnsName: rsAliasDNSName
                    )
                    recordSets.append(Route53RecordSet(
                        name: rsName,
                        type: rsType,
                        ttl: rsTTL,
                        values: rsValues,
                        aliasTarget: aliasTarget,
                        weight: rsWeight,
                        setIdentifier: rsSetIdentifier.isEmpty ? nil : rsSetIdentifier
                    ))
                    inRecordSet = false
                default: break
                }
            }
        } else {
            switch elementName {
            case "IsTruncated": isTruncated = text.lowercased() == "true"
            case "NextRecordName": nextRecordName = text
            case "NextRecordType": nextRecordType = text
            default: break
            }
        }

        elementStack.removeLast()
        currentElement = ""
    }
}

// MARK: - Create Hosted Zone Response Parser

final class Route53CreateZoneResponseParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var inHostedZone = false
    private var inConfig = false
    private var zoneId = ""
    private var zoneName = ""

    func parse(data: Data) throws -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw Route53XMLParseError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return normalizeZoneId(zoneId)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "HostedZone" {
            inHostedZone = true
        } else if elementName == "Config" {
            inConfig = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inHostedZone && !inConfig {
            switch elementName {
            case "Id": zoneId = text
            case "Name": zoneName = text
            case "HostedZone": inHostedZone = false
            default: break
            }
        } else if inConfig && elementName == "Config" {
            inConfig = false
        }

        currentElement = ""
    }
}

// MARK: - Helpers

/// Strips the `/hostedzone/` prefix from zone IDs returned by Route 53.
func normalizeZoneId(_ rawId: String) -> String {
    if rawId.hasPrefix("/hostedzone/") {
        return String(rawId.dropFirst("/hostedzone/".count))
    }
    return rawId
}
