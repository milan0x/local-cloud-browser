import Foundation

final class OpenSearchService: LocalStackService {
    // MARK: - Domain Operations

    func listDomains(region: String? = nil) async throws -> [OpenSearchDomain] {
        let listResponse = try await client.opensearchRequest(
            action: "ListDomainNames",
            method: "GET",
            path: "/domain",
            region: region
        )
        guard let json = try JSONSerialization.jsonObject(with: listResponse.data) as? [String: Any],
              let domainNames = json["DomainNames"] as? [[String: Any]] else {
            return []
        }
        var domains: [OpenSearchDomain] = []
        for entry in domainNames {
            guard let name = entry["DomainName"] as? String else { continue }
            do {
                let domain = try await describeDomain(name: name)
                domains.append(domain)
            } catch {
                // If describe fails for one domain, still list the rest
                domains.append(OpenSearchDomain(domainName: name,
                                                engineVersion: entry["EngineType"] as? String ?? ""))
            }
        }
        return domains
    }

    func describeDomain(name: String) async throws -> OpenSearchDomain {
        let response = try await client.opensearchRequest(
            action: "DescribeDomain",
            method: "GET",
            path: "/opensearch/domain/\(name)"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let status = json["DomainStatus"] as? [String: Any] else {
            return OpenSearchDomain(domainName: name)
        }
        return OpenSearchDomain(json: status)
    }

    func createDomain(
        name: String,
        engineVersion: String,
        instanceType: String,
        instanceCount: Int
    ) async throws {
        let payload: [String: Any] = [
            "DomainName": name,
            "EngineVersion": engineVersion,
            "ClusterConfig": [
                "InstanceType": instanceType,
                "InstanceCount": instanceCount,
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.opensearchRequest(
            action: "CreateDomain",
            method: "POST",
            path: "/opensearch/domain",
            body: body
        )
    }

    func deleteDomain(name: String) async throws {
        _ = try await client.opensearchRequest(
            action: "DeleteDomain",
            method: "DELETE",
            path: "/opensearch/domain/\(name)"
        )
    }

    // MARK: - Cluster REST API (direct to domain endpoint)

    func fetchClusterHealth(endpoint: String) async throws -> ClusterHealth {
        guard let url = URL(string: "\(endpoint)/_cluster/health") else {
            throw LocalStackClientError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ClusterHealth(json: json)
    }

    func fetchIndices(endpoint: String) async throws -> [OpenSearchIndex] {
        guard let url = URL(string: "\(endpoint)/_cat/indices?format=json") else {
            throw LocalStackClientError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.map { OpenSearchIndex(json: $0) }
    }
}
