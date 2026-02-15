import Foundation

@MainActor
final class ResourceGroupsService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Read Operations

    func listGroups() async throws -> [ResourceGroupSummary] {
        var allGroups: [ResourceGroupSummary] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let body = payload.isEmpty ? nil : try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.resourceGroupsRequest(
                action: "ListGroups",
                method: "POST",
                path: "/groups-list",
                body: body
            )
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let identifiers = json["GroupIdentifiers"] as? [[String: Any]] {
                allGroups.append(contentsOf: identifiers.map { ResourceGroupSummary(from: $0) })
            } else if let groups = json["Groups"] as? [[String: Any]] {
                allGroups.append(contentsOf: groups.map { ResourceGroupSummary(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allGroups
    }

    func getGroup(name: String) async throws -> ResourceGroupDetail {
        let payload: [String: Any] = ["GroupName": name]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.resourceGroupsRequest(
            action: "GetGroup",
            method: "POST",
            path: "/get-group",
            body: body
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ResourceGroupDetail(from: json)
    }

    func getGroupQuery(name: String) async throws -> ResourceGroupQuery {
        let payload: [String: Any] = ["GroupName": name]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.resourceGroupsRequest(
            action: "GetGroupQuery",
            method: "POST",
            path: "/get-group-query",
            body: body
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groupQuery = json["GroupQuery"] as? [String: Any],
              let resourceQuery = groupQuery["ResourceQuery"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ResourceGroupQuery(from: resourceQuery)
    }

    func listGroupResources(name: String) async throws -> [GroupResource] {
        var allResources: [GroupResource] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = ["GroupName": name]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let body = try JSONSerialization.data(withJSONObject: payload)
            let data = try await client.resourceGroupsRequest(
                action: "ListGroupResources",
                method: "POST",
                path: "/list-group-resources",
                body: body
            )
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let resources = json["ResourceIdentifiers"] as? [[String: Any]] {
                allResources.append(contentsOf: resources.map { GroupResource(from: $0) })
            } else if let resources = json["Resources"] as? [[String: Any]] {
                allResources.append(contentsOf: resources.map { GroupResource(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allResources
    }

    // MARK: - Write Operations

    func createGroup(
        name: String,
        description: String,
        tagFilters: [TagFilter],
        resourceTypeFilters: [String]
    ) async throws {
        var queryObj: [String: Any] = [:]
        if !tagFilters.isEmpty {
            queryObj["TagFilters"] = tagFilters.map { filter -> [String: Any] in
                var dict: [String: Any] = ["Key": filter.key]
                if !filter.values.isEmpty {
                    dict["Values"] = filter.values
                }
                return dict
            }
        }
        if !resourceTypeFilters.isEmpty {
            queryObj["ResourceTypeFilters"] = resourceTypeFilters
        } else {
            queryObj["ResourceTypeFilters"] = ["AWS::AllSupported"]
        }
        let queryString = String(data: try JSONSerialization.data(withJSONObject: queryObj), encoding: .utf8) ?? "{}"

        var payload: [String: Any] = [
            "Name": name,
            "ResourceQuery": [
                "Type": "TAG_FILTERS_1_0",
                "Query": queryString,
            ] as [String: Any],
        ]
        if !description.isEmpty {
            payload["Description"] = description
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.resourceGroupsRequest(
            action: "CreateGroup",
            method: "POST",
            path: "/groups",
            body: body
        )
    }

    func updateGroup(name: String, description: String) async throws {
        var payload: [String: Any] = ["GroupName": name]
        payload["Description"] = description
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.resourceGroupsRequest(
            action: "UpdateGroup",
            method: "POST",
            path: "/update-group",
            body: body
        )
    }

    func deleteGroup(name: String) async throws {
        let payload: [String: Any] = ["GroupName": name]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.resourceGroupsRequest(
            action: "DeleteGroup",
            method: "POST",
            path: "/delete-group",
            body: body
        )
    }
}
