import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Redshift Models")
struct RedshiftModelTests {

    // MARK: - RedshiftCluster.statusBadgeColor

    @Test("statusBadgeColor maps statuses correctly")
    func statusBadgeColor() {
        #expect(RedshiftCluster(clusterStatus: "available").statusBadgeColor == "green")
        #expect(RedshiftCluster(clusterStatus: "creating").statusBadgeColor == "blue")
        #expect(RedshiftCluster(clusterStatus: "modifying").statusBadgeColor == "blue")
        #expect(RedshiftCluster(clusterStatus: "deleting").statusBadgeColor == "red")
        #expect(RedshiftCluster(clusterStatus: "paused").statusBadgeColor == "orange")
        #expect(RedshiftCluster(clusterStatus: "unknown").statusBadgeColor == "gray")
    }

    // MARK: - endpointString

    @Test("endpointString combines address and port")
    func endpointString() {
        let cluster = RedshiftCluster(
            clusterIdentifier: "test",
            endpointAddress: "my-cluster.abc.us-east-1.redshift.amazonaws.com",
            endpointPort: 5439
        )
        #expect(cluster.endpointString == "my-cluster.abc.us-east-1.redshift.amazonaws.com:5439")
    }

    @Test("endpointString empty when no address")
    func endpointStringEmpty() {
        let cluster = RedshiftCluster(clusterIdentifier: "test")
        #expect(cluster.endpointString == "")
    }

    // MARK: - CLI

    @Test("describeClustersCLI generates valid command")
    func describeClustersCLI() {
        let cluster = RedshiftCluster(clusterIdentifier: "my-cluster")
        let cli = cluster.describeClustersCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws redshift describe-clusters"))
        #expect(cli.contains("my-cluster"))
    }

    @Test("listClustersCLI generates valid command")
    func listClustersCLI() {
        let cli = RedshiftCluster.listClustersCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws redshift describe-clusters"))
    }

    // MARK: - RedshiftClusterListParser

    @Test("parses clusters from XML")
    func parseClusterXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DescribeClustersResponse>
            <DescribeClustersResult>
                <Clusters>
                    <Cluster>
                        <ClusterIdentifier>my-cluster</ClusterIdentifier>
                        <ClusterStatus>available</ClusterStatus>
                        <NodeType>dc2.large</NodeType>
                        <NumberOfNodes>2</NumberOfNodes>
                        <MasterUsername>admin</MasterUsername>
                        <DBName>dev</DBName>
                        <Endpoint>
                            <Address>my-cluster.abc.us-east-1.redshift.amazonaws.com</Address>
                            <Port>5439</Port>
                        </Endpoint>
                        <Encrypted>true</Encrypted>
                        <PubliclyAccessible>false</PubliclyAccessible>
                        <ClusterCreateTime>2024-01-15T10:00:00Z</ClusterCreateTime>
                        <ClusterVersion>1.0</ClusterVersion>
                    </Cluster>
                </Clusters>
            </DescribeClustersResult>
        </DescribeClustersResponse>
        """
        let data = xml.data(using: .utf8)!
        let clusters = try RedshiftClusterListParser.parse(data)

        #expect(clusters.count == 1)
        #expect(clusters[0].clusterIdentifier == "my-cluster")
        #expect(clusters[0].clusterStatus == "available")
        #expect(clusters[0].nodeType == "dc2.large")
        #expect(clusters[0].numberOfNodes == 2)
        #expect(clusters[0].masterUsername == "admin")
        #expect(clusters[0].endpointAddress == "my-cluster.abc.us-east-1.redshift.amazonaws.com")
        #expect(clusters[0].endpointPort == 5439)
        #expect(clusters[0].encrypted == true)
        #expect(clusters[0].publiclyAccessible == false)
    }

    @Test("parses empty cluster list")
    func parseEmptyClusterXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DescribeClustersResponse>
            <DescribeClustersResult>
                <Clusters/>
            </DescribeClustersResult>
        </DescribeClustersResponse>
        """
        let data = xml.data(using: .utf8)!
        let clusters = try RedshiftClusterListParser.parse(data)
        #expect(clusters.isEmpty)
    }
}
