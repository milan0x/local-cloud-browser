import Foundation

final class ResourceGroupsService: BaseService {
    // MARK: - Read Operations

    func listGroupsPage(region: String? = nil, token: String? = nil) async throws -> ([ResourceGroupSummary], String?) {
        var payload: [String: Any] = [:]
        if let token {
            payload["NextToken"] = token
        }
        let body = payload.isEmpty ? nil : try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.resourceGroupsRequest(
            action: "ListGroups",
            method: "POST",
            path: "/groups-list",
            body: body,
            region: region
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        var groups: [ResourceGroupSummary] = []
        if let identifiers = json["GroupIdentifiers"] as? [[String: Any]] {
            groups.append(contentsOf: identifiers.map { ResourceGroupSummary(from: $0) })
        } else if let groupList = json["Groups"] as? [[String: Any]] {
            groups.append(contentsOf: groupList.map { ResourceGroupSummary(from: $0) })
        }
        return (groups, json["NextToken"] as? String)
    }

    func listGroups(region: String? = nil) async throws -> [ResourceGroupSummary] {
        var allGroups: [ResourceGroupSummary] = []
        var nextToken: String?

        repeat {
            let (groups, token) = try await listGroupsPage(region: region, token: nextToken)
            allGroups.append(contentsOf: groups)
            nextToken = token
            if allGroups.count >= 10_000 { break }
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
            throw CloudClientError.invalidURL
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
            throw CloudClientError.invalidURL
        }
        return ResourceGroupQuery(from: resourceQuery)
    }

    func listGroupResourcesPage(name: String, token: String? = nil) async throws -> ([GroupResource], String?) {
        var payload: [String: Any] = ["GroupName": name]
        if let token {
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
            return ([], nil)
        }
        var resources: [GroupResource] = []
        if let identifiers = json["ResourceIdentifiers"] as? [[String: Any]] {
            resources.append(contentsOf: identifiers.map { GroupResource(from: $0) })
        } else if let resList = json["Resources"] as? [[String: Any]] {
            resources.append(contentsOf: resList.map { GroupResource(from: $0) })
        }
        return (resources, json["NextToken"] as? String)
    }

    func listGroupResources(name: String) async throws -> [GroupResource] {
        var allResources: [GroupResource] = []
        var nextToken: String?

        repeat {
            let (resources, token) = try await listGroupResourcesPage(name: name, token: nextToken)
            allResources.append(contentsOf: resources)
            nextToken = token
            if allResources.count >= 10_000 { break }
        } while nextToken != nil

        return allResources
    }

    // MARK: - Local Query Cache

    /// Moto does not implement GetGroupQuery, so we cache queries locally
    /// when groups are created through the app.
    private static let queryStoreKey = "resourceGroupQueryCache"

    static func cachedQuery(for groupName: String) -> ResourceGroupQuery? {
        guard let store = UserDefaults.standard.dictionary(forKey: queryStoreKey),
              let entry = store[groupName] as? [String: Any] else { return nil }
        return ResourceGroupQuery(
            type: entry["type"] as? String ?? "TAG_FILTERS_1_0",
            tagFilters: (entry["tagFilters"] as? [[String: Any]])?.map {
                TagFilter(key: $0["key"] as? String ?? "",
                          values: $0["values"] as? [String] ?? [])
            } ?? [],
            resourceTypeFilters: entry["resourceTypeFilters"] as? [String] ?? []
        )
    }

    private static func cacheQuery(name: String, tagFilters: [TagFilter], resourceTypeFilters: [String]) {
        var store = UserDefaults.standard.dictionary(forKey: queryStoreKey) ?? [:]
        store[name] = [
            "type": "TAG_FILTERS_1_0",
            "tagFilters": tagFilters.map { ["key": $0.key, "values": $0.values] as [String: Any] },
            "resourceTypeFilters": resourceTypeFilters.isEmpty ? ["AWS::AllSupported"] : resourceTypeFilters,
        ] as [String: Any]
        UserDefaults.standard.set(store, forKey: queryStoreKey)
    }

    private static func removeCachedQuery(name: String) {
        var store = UserDefaults.standard.dictionary(forKey: queryStoreKey) ?? [:]
        store.removeValue(forKey: name)
        UserDefaults.standard.set(store, forKey: queryStoreKey)
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
                [
                    "Key": filter.key,
                    "Values": filter.values,
                ] as [String: Any]
            }
        }
        let effectiveTypeFilters: [String]
        if !resourceTypeFilters.isEmpty {
            queryObj["ResourceTypeFilters"] = resourceTypeFilters
            effectiveTypeFilters = resourceTypeFilters
        } else {
            queryObj["ResourceTypeFilters"] = ["AWS::AllSupported"]
            effectiveTypeFilters = ["AWS::AllSupported"]
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

        // Cache the query locally — moto doesn't implement GetGroupQuery
        Self.cacheQuery(name: name, tagFilters: tagFilters, resourceTypeFilters: effectiveTypeFilters)
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
        Self.removeCachedQuery(name: name)
    }
}
