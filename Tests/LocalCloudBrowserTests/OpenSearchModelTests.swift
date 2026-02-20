import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("OpenSearch Models")
struct OpenSearchModelTests {

    // MARK: - OpenSearchDomain.status

    @Test("status returns Active when created and not processing")
    func statusActive() {
        let domain = OpenSearchDomain(created: true, deleted: false)
        #expect(domain.status == "Active")
    }

    @Test("status returns Processing when processing")
    func statusProcessing() {
        let domain = OpenSearchDomain(processing: true, created: true)
        #expect(domain.status == "Processing")
    }

    @Test("status returns Deleting when deleted")
    func statusDeleting() {
        let domain = OpenSearchDomain(deleted: true)
        #expect(domain.status == "Deleting")
    }

    @Test("status returns Unknown when not created")
    func statusUnknown() {
        let domain = OpenSearchDomain(created: false)
        #expect(domain.status == "Unknown")
    }

    // MARK: - statusColor

    @Test("statusColor maps statuses correctly")
    func statusColor() {
        #expect(OpenSearchDomain(created: true).statusColor == "green")
        #expect(OpenSearchDomain(processing: true, created: true).statusColor == "blue")
        #expect(OpenSearchDomain(deleted: true).statusColor == "red")
        #expect(OpenSearchDomain(created: false).statusColor == "gray")
    }

    // MARK: - engineDisplayName

    @Test("engineDisplayName replaces underscores")
    func engineDisplayName() {
        let domain = OpenSearchDomain(engineVersion: "OpenSearch_2.11")
        #expect(domain.engineDisplayName == "OpenSearch 2.11")
    }

    // MARK: - init(json:)

    @Test("parses from JSON dict")
    func initFromJSON() {
        let domain = OpenSearchDomain(json: [
            "DomainName": "my-domain",
            "DomainId": "000/my-domain",
            "ARN": "arn:aws:es:us-east-1:000:domain/my-domain",
            "EngineVersion": "OpenSearch_2.11",
            "Endpoint": "search-my-domain.us-east-1.es.amazonaws.com",
            "Processing": false,
            "Created": true,
            "Deleted": false,
            "ClusterConfig": [
                "InstanceType": "t3.small.search",
                "InstanceCount": 2,
            ],
            "EBSOptions": [
                "EBSEnabled": true,
                "VolumeType": "gp3",
                "VolumeSize": 100,
            ],
        ])
        #expect(domain.domainName == "my-domain")
        #expect(domain.engineVersion == "OpenSearch_2.11")
        #expect(domain.instanceType == "t3.small.search")
        #expect(domain.instanceCount == 2)
        #expect(domain.ebsEnabled == true)
        #expect(domain.volumeType == "gp3")
        #expect(domain.volumeSize == 100)
    }

    // MARK: - ClusterHealth

    @Test("ClusterHealth parses from JSON")
    func clusterHealthInit() {
        let health = ClusterHealth(json: [
            "cluster_name": "my-cluster",
            "status": "green",
            "number_of_nodes": 3,
            "active_shards": 10,
            "relocating_shards": 0,
            "initializing_shards": 0,
            "unassigned_shards": 0,
        ])
        #expect(health.clusterName == "my-cluster")
        #expect(health.status == "green")
        #expect(health.numberOfNodes == 3)
        #expect(health.activeShards == 10)
    }

    // MARK: - OpenSearchIndex

    @Test("OpenSearchIndex parses from JSON")
    func indexInit() {
        let index = OpenSearchIndex(json: [
            "index": "my-index",
            "health": "green",
            "status": "open",
            "docs.count": "1000",
            "store.size": "5mb",
        ])
        #expect(index.name == "my-index")
        #expect(index.health == "green")
        #expect(index.status == "open")
        #expect(index.docCount == "1000")
        #expect(index.storeSize == "5mb")
    }

    // MARK: - CLI

    @Test("describeDomainCLI generates valid command")
    func describeDomainCLI() {
        let domain = OpenSearchDomain(domainName: "my-domain")
        let cli = domain.describeDomainCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws opensearch describe-domain"))
        #expect(cli.contains("my-domain"))
    }

    @Test("listDomainsCLI generates valid command")
    func listDomainsCLI() {
        let cli = OpenSearchDomain.listDomainsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws opensearch list-domain-names"))
    }
}
