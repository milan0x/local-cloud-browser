import Foundation

@MainActor
final class RedshiftService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Cluster Operations

    func describeClusters() async throws -> [RedshiftCluster] {
        let data = try await client.redshiftRequest(action: "DescribeClusters")
        return try RedshiftClusterListParser.parse(data)
    }

    func createCluster(
        id: String,
        masterUsername: String,
        masterPassword: String,
        nodeType: String,
        numberOfNodes: Int,
        dbName: String,
        port: Int
    ) async throws {
        var params: [String: String] = [
            "ClusterIdentifier": id,
            "MasterUsername": masterUsername,
            "MasterUserPassword": masterPassword,
            "NodeType": nodeType,
            "NumberOfNodes": String(numberOfNodes),
        ]
        if !dbName.isEmpty {
            params["DBName"] = dbName
        }
        if port != 5439 {
            params["Port"] = String(port)
        }
        _ = try await client.redshiftRequest(action: "CreateCluster", params: params)
    }

    func deleteCluster(id: String, skipFinalSnapshot: Bool = true) async throws {
        var params: [String: String] = [
            "ClusterIdentifier": id,
            "SkipFinalClusterSnapshot": skipFinalSnapshot ? "true" : "false",
        ]
        if !skipFinalSnapshot {
            params["FinalClusterSnapshotIdentifier"] = "\(id)-final-snapshot"
        }
        _ = try await client.redshiftRequest(action: "DeleteCluster", params: params)
    }
}
