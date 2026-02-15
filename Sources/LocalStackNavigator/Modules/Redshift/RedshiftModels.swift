import Foundation

struct RedshiftCluster: Identifiable, Hashable {
    let clusterIdentifier: String
    let clusterStatus: String
    let nodeType: String
    let numberOfNodes: Int
    let masterUsername: String
    let dbName: String
    let endpointAddress: String
    let endpointPort: Int
    let encrypted: Bool
    let publiclyAccessible: Bool
    let createTime: String
    let clusterVersion: String

    var id: String { clusterIdentifier }

    var statusBadgeColor: String {
        switch clusterStatus {
        case "available": return "green"
        case "creating", "modifying": return "blue"
        case "deleting": return "red"
        case "paused": return "orange"
        default: return "gray"
        }
    }

    var endpointString: String {
        guard !endpointAddress.isEmpty else { return "" }
        return "\(endpointAddress):\(endpointPort)"
    }

    init(clusterIdentifier: String = "", clusterStatus: String = "",
         nodeType: String = "", numberOfNodes: Int = 1,
         masterUsername: String = "", dbName: String = "dev",
         endpointAddress: String = "", endpointPort: Int = 5439,
         encrypted: Bool = false, publiclyAccessible: Bool = false,
         createTime: String = "", clusterVersion: String = "") {
        self.clusterIdentifier = clusterIdentifier
        self.clusterStatus = clusterStatus
        self.nodeType = nodeType
        self.numberOfNodes = numberOfNodes
        self.masterUsername = masterUsername
        self.dbName = dbName
        self.endpointAddress = endpointAddress
        self.endpointPort = endpointPort
        self.encrypted = encrypted
        self.publiclyAccessible = publiclyAccessible
        self.createTime = createTime
        self.clusterVersion = clusterVersion
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeClustersCLI(endpointUrl: String, region: String) -> String {
        [
            "aws redshift describe-clusters \\",
            "  --cluster-identifier '\(Self.shellEscape(clusterIdentifier))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    func deleteClusterCLI(endpointUrl: String, region: String) -> String {
        [
            "aws redshift delete-cluster \\",
            "  --cluster-identifier '\(Self.shellEscape(clusterIdentifier))' \\",
            "  --skip-final-cluster-snapshot \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    static func listClustersCLI(endpointUrl: String, region: String) -> String {
        [
            "aws redshift describe-clusters \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }
}
