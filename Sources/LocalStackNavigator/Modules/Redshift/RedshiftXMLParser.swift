import Foundation

/// Parses Redshift Query/XML responses for DescribeClusters.
///
/// Handles nested `<Endpoint>` blocks inside `<Cluster>` members:
/// ```xml
/// <Clusters><member>
///   <ClusterIdentifier>my-cluster</ClusterIdentifier>
///   <Endpoint><Address>...</Address><Port>5439</Port></Endpoint>
///   ...
/// </member></Clusters>
/// ```
final class RedshiftClusterListParser: NSObject, XMLParserDelegate {
    private var clusters: [RedshiftCluster] = []
    private var currentText = ""
    private var inCluster = false
    private var inEndpoint = false

    // Current cluster fields
    private var clusterIdentifier = ""
    private var clusterStatus = ""
    private var nodeType = ""
    private var numberOfNodes = 1
    private var masterUsername = ""
    private var dbName = ""
    private var endpointAddress = ""
    private var endpointPort = 5439
    private var encrypted = false
    private var publiclyAccessible = false
    private var createTime = ""
    private var clusterVersion = ""

    static func parse(_ data: Data) throws -> [RedshiftCluster] {
        let p = RedshiftClusterListParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else {
            let desc = parser.parserError?.localizedDescription ?? "Unknown XML parse error"
            throw SNSXMLParseError.parseFailure(desc)
        }
        return p.clusters
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
        if elementName == "member" {
            inCluster = true
            clusterIdentifier = ""
            clusterStatus = ""
            nodeType = ""
            numberOfNodes = 1
            masterUsername = ""
            dbName = ""
            endpointAddress = ""
            endpointPort = 5439
            encrypted = false
            publiclyAccessible = false
            createTime = ""
            clusterVersion = ""
        } else if elementName == "Endpoint" && inCluster {
            inEndpoint = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inCluster {
            if inEndpoint {
                switch elementName {
                case "Address": endpointAddress = text
                case "Port": endpointPort = Int(text) ?? 5439
                case "Endpoint": inEndpoint = false
                default: break
                }
            } else {
                switch elementName {
                case "ClusterIdentifier": clusterIdentifier = text
                case "ClusterStatus": clusterStatus = text
                case "NodeType": nodeType = text
                case "NumberOfNodes": numberOfNodes = Int(text) ?? 1
                case "MasterUsername": masterUsername = text
                case "DBName": dbName = text
                case "Encrypted": encrypted = text.lowercased() == "true"
                case "PubliclyAccessible": publiclyAccessible = text.lowercased() == "true"
                case "ClusterCreateTime": createTime = text
                case "ClusterVersion": clusterVersion = text
                case "member":
                    guard !clusterIdentifier.isEmpty else { break }
                    clusters.append(RedshiftCluster(
                        clusterIdentifier: clusterIdentifier,
                        clusterStatus: clusterStatus,
                        nodeType: nodeType,
                        numberOfNodes: numberOfNodes,
                        masterUsername: masterUsername,
                        dbName: dbName,
                        endpointAddress: endpointAddress,
                        endpointPort: endpointPort,
                        encrypted: encrypted,
                        publiclyAccessible: publiclyAccessible,
                        createTime: createTime,
                        clusterVersion: clusterVersion
                    ))
                    inCluster = false
                default: break
                }
            }
        }

        currentText = ""
    }
}
