import Foundation

final class APIGatewayService: BaseService {
    // MARK: - REST API Operations

    func listRestApis(region: String? = nil) async throws -> [RestApi] {
        let response = try await client.apiGatewayRequest(
            action: "GetRestApis",
            method: "GET",
            path: "",
            region: region
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let items = json["item"] as? [[String: Any]] else {
            return []
        }
        return items.map { RestApi(from: $0) }
    }

    func getRestApi(id: String) async throws -> RestApi {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response = try await client.apiGatewayRequest(
            action: "GetRestApi",
            method: "GET",
            path: "/\(escaped)"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return RestApi(from: json)
    }

    func createRestApi(name: String, description: String = "", endpointType: String = "REGIONAL") async throws {
        var payload: [String: Any] = ["name": name]
        if !description.isEmpty {
            payload["description"] = description
        }
        payload["endpointConfiguration"] = ["types": [endpointType]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "CreateRestApi",
            method: "POST",
            path: "",
            body: body
        )
    }

    func deleteRestApi(id: String) async throws {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await client.apiGatewayRequest(
            action: "DeleteRestApi",
            method: "DELETE",
            path: "/\(escaped)"
        )
    }

    // MARK: - Resource Operations

    func getResources(apiId: String) async throws -> [APIResource] {
        let escaped = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let response = try await client.apiGatewayRequest(
            action: "GetResources",
            method: "GET",
            path: "/\(escaped)/resources"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let items = json["item"] as? [[String: Any]] else {
            return []
        }
        return items.map { APIResource(from: $0) }
    }

    func createResource(apiId: String, parentId: String, pathPart: String) async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedParent = parentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? parentId
        let payload: [String: Any] = ["pathPart": pathPart]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "CreateResource",
            method: "POST",
            path: "/\(escapedApi)/resources/\(escapedParent)",
            body: body
        )
    }

    func deleteResource(apiId: String, resourceId: String) async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedRes = resourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourceId
        _ = try await client.apiGatewayRequest(
            action: "DeleteResource",
            method: "DELETE",
            path: "/\(escapedApi)/resources/\(escapedRes)"
        )
    }

    // MARK: - Method Operations

    func getMethod(apiId: String, resourceId: String, httpMethod: String) async throws -> APIMethod {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedRes = resourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourceId
        let response = try await client.apiGatewayRequest(
            action: "GetMethod",
            method: "GET",
            path: "/\(escapedApi)/resources/\(escapedRes)/methods/\(httpMethod)"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return APIMethod(from: json)
    }

    func putMethod(apiId: String, resourceId: String, httpMethod: String, authorizationType: String = "NONE") async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedRes = resourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourceId
        let payload: [String: Any] = ["authorizationType": authorizationType]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "PutMethod",
            method: "PUT",
            path: "/\(escapedApi)/resources/\(escapedRes)/methods/\(httpMethod)",
            body: body
        )
    }

    func deleteMethod(apiId: String, resourceId: String, httpMethod: String) async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedRes = resourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourceId
        _ = try await client.apiGatewayRequest(
            action: "DeleteMethod",
            method: "DELETE",
            path: "/\(escapedApi)/resources/\(escapedRes)/methods/\(httpMethod)"
        )
    }

    // MARK: - Integration Operations

    func putIntegration(
        apiId: String,
        resourceId: String,
        httpMethod: String,
        type: String,
        uri: String = "",
        integrationHttpMethod: String = ""
    ) async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedRes = resourceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourceId
        var payload: [String: Any] = ["type": type]
        if !uri.isEmpty {
            payload["uri"] = uri
        }
        if !integrationHttpMethod.isEmpty {
            payload["integrationHttpMethod"] = integrationHttpMethod
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "PutIntegration",
            method: "PUT",
            path: "/\(escapedApi)/resources/\(escapedRes)/methods/\(httpMethod)/integration",
            body: body
        )
    }

    // MARK: - Deployment Operations

    func getDeployments(apiId: String) async throws -> [APIDeployment] {
        let escaped = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let response = try await client.apiGatewayRequest(
            action: "GetDeployments",
            method: "GET",
            path: "/\(escaped)/deployments"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let items = json["item"] as? [[String: Any]] else {
            return []
        }
        return items.map { APIDeployment(from: $0) }
    }

    func createDeployment(apiId: String, description: String = "") async throws {
        let escaped = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        var payload: [String: Any] = [:]
        if !description.isEmpty {
            payload["description"] = description
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "CreateDeployment",
            method: "POST",
            path: "/\(escaped)/deployments",
            body: body
        )
    }

    // MARK: - Stage Operations

    func getStages(apiId: String) async throws -> [APIStage] {
        let escaped = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let response = try await client.apiGatewayRequest(
            action: "GetStages",
            method: "GET",
            path: "/\(escaped)/stages"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let items = json["item"] as? [[String: Any]] else {
            return []
        }
        return items.map { APIStage(from: $0) }
    }

    func createStage(apiId: String, stageName: String, deploymentId: String, description: String = "") async throws {
        let escaped = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        var payload: [String: Any] = [
            "stageName": stageName,
            "deploymentId": deploymentId,
        ]
        if !description.isEmpty {
            payload["description"] = description
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.apiGatewayRequest(
            action: "CreateStage",
            method: "POST",
            path: "/\(escaped)/stages",
            body: body
        )
    }

    func deleteStage(apiId: String, stageName: String) async throws {
        let escapedApi = apiId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? apiId
        let escapedStage = stageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stageName
        _ = try await client.apiGatewayRequest(
            action: "DeleteStage",
            method: "DELETE",
            path: "/\(escapedApi)/stages/\(escapedStage)"
        )
    }
}
