import Foundation

struct RestApi: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let createdDate: String
    let version: String
    let apiKeySource: String
    let endpointConfigurationTypes: [String]

    init(from dict: [String: Any]) {
        id = dict["id"] as? String ?? ""
        name = dict["name"] as? String ?? ""
        description = dict["description"] as? String ?? ""
        createdDate = dict["createdDate"] as? String ?? ""
        version = dict["version"] as? String ?? ""
        apiKeySource = dict["apiKeySource"] as? String ?? ""
        if let config = dict["endpointConfiguration"] as? [String: Any],
           let types = config["types"] as? [String] {
            endpointConfigurationTypes = types
        } else {
            endpointConfigurationTypes = []
        }
    }

    var endpointType: String {
        endpointConfigurationTypes.first ?? "REGIONAL"
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func getRestApiCLI(endpointUrl: String, region: String) -> String {
        [
            "aws apigateway get-rest-api \\",
            "  --rest-api-id '\(Self.shellEscape(id))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func getResourcesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws apigateway get-resources \\",
            "  --rest-api-id '\(Self.shellEscape(id))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listRestApisCLI(endpointUrl: String, region: String) -> String {
        [
            "aws apigateway get-rest-apis \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct APIResource: Identifiable, Hashable {
    let id: String
    let parentId: String
    let path: String
    let pathPart: String
    let methods: [String]

    var isRoot: Bool { path == "/" }

    init(from dict: [String: Any]) {
        id = dict["id"] as? String ?? ""
        parentId = dict["parentId"] as? String ?? ""
        path = dict["path"] as? String ?? ""
        pathPart = dict["pathPart"] as? String ?? ""
        if let methodMap = dict["resourceMethods"] as? [String: Any] {
            methods = Array(methodMap.keys).sorted()
        } else {
            methods = []
        }
    }
}

struct APIMethod: Identifiable, Hashable {
    let httpMethod: String
    let authorizationType: String
    let apiKeyRequired: Bool
    let integration: APIIntegration?

    var id: String { httpMethod }

    init(from dict: [String: Any]) {
        httpMethod = dict["httpMethod"] as? String ?? ""
        authorizationType = dict["authorizationType"] as? String ?? "NONE"
        apiKeyRequired = dict["apiKeyRequired"] as? Bool ?? false
        if let intDict = dict["methodIntegration"] as? [String: Any] {
            integration = APIIntegration(from: intDict)
        } else {
            integration = nil
        }
    }
}

struct APIIntegration: Hashable {
    let type: String
    let httpMethod: String
    let uri: String
    let integrationHttpMethod: String

    init(from dict: [String: Any]) {
        type = dict["type"] as? String ?? ""
        httpMethod = dict["httpMethod"] as? String ?? ""
        uri = dict["uri"] as? String ?? ""
        integrationHttpMethod = dict["integrationHttpMethod"] as? String ?? ""
    }
}

struct APIDeployment: Identifiable, Hashable {
    let id: String
    let description: String
    let createdDate: String

    init(from dict: [String: Any]) {
        id = dict["id"] as? String ?? ""
        description = dict["description"] as? String ?? ""
        createdDate = dict["createdDate"] as? String ?? ""
    }
}

struct APIStage: Identifiable, Hashable {
    let stageName: String
    let deploymentId: String
    let description: String
    let createdDate: String
    let variables: [String: String]

    var id: String { stageName }

    init(from dict: [String: Any]) {
        stageName = dict["stageName"] as? String ?? ""
        deploymentId = dict["deploymentId"] as? String ?? ""
        description = dict["description"] as? String ?? ""
        createdDate = dict["createdDate"] as? String ?? ""
        variables = dict["stageVariables"] as? [String: String] ?? [:]
    }

    func invokeUrl(apiId: String, domain: String, port: Int?) -> String {
        let portSuffix = port.map { ":\($0)" } ?? ""
        return "http://\(apiId).\(domain)\(portSuffix)/\(stageName)/"
    }

    func pathStyleInvokeUrl(apiId: String, endpoint: String) -> String {
        "\(endpoint)/_aws/execute-api/\(apiId)/\(stageName)/"
    }
}
