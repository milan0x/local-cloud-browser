import Foundation

@MainActor
final class LambdaService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Function Operations

    func listFunctions() async throws -> [LambdaFunction] {
        var allFunctions: [LambdaFunction] = []
        var marker: String? = nil

        repeat {
            var path = "/functions"
            if let marker {
                path += "?Marker=\(marker)"
            }
            let response = try await client.lambdaRequest(
                action: "ListFunctions",
                method: "GET",
                path: path
            )
            guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
                break
            }
            if let functions = json["Functions"] as? [[String: Any]] {
                allFunctions.append(contentsOf: functions.map { LambdaFunction(from: $0) })
            }
            marker = json["NextMarker"] as? String
        } while marker != nil

        return allFunctions
    }

    func getFunction(name: String) async throws -> LambdaFunction {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let response = try await client.lambdaRequest(
            action: "GetFunction",
            method: "GET",
            path: "/functions/\(escaped)"
        )
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        let config = json["Configuration"] as? [String: Any] ?? json
        return LambdaFunction(from: config)
    }

    func createFunction(
        name: String,
        runtime: String,
        handler: String,
        role: String,
        zipData: Data,
        description: String? = nil,
        timeout: Int = 3,
        memorySize: Int = 128,
        environment: [String: String] = [:]
    ) async throws {
        var payload: [String: Any] = [
            "FunctionName": name,
            "Runtime": runtime,
            "Handler": handler,
            "Role": role,
            "Code": ["ZipFile": zipData.base64EncodedString()],
            "Timeout": timeout,
            "MemorySize": memorySize,
        ]
        if let description, !description.isEmpty {
            payload["Description"] = description
        }
        if !environment.isEmpty {
            payload["Environment"] = ["Variables": environment]
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.lambdaRequest(
            action: "CreateFunction",
            method: "POST",
            path: "/functions",
            body: body
        )
    }

    func updateFunctionConfiguration(
        name: String,
        description: String? = nil,
        timeout: Int? = nil,
        memorySize: Int? = nil,
        handler: String? = nil,
        runtime: String? = nil,
        environment: [String: String]? = nil
    ) async throws {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        var payload: [String: Any] = [:]
        if let description { payload["Description"] = description }
        if let timeout { payload["Timeout"] = timeout }
        if let memorySize { payload["MemorySize"] = memorySize }
        if let handler { payload["Handler"] = handler }
        if let runtime { payload["Runtime"] = runtime }
        if let environment { payload["Environment"] = ["Variables": environment] }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.lambdaRequest(
            action: "UpdateFunctionConfiguration",
            method: "PUT",
            path: "/functions/\(escaped)/configuration",
            body: body
        )
    }

    func updateFunctionCode(name: String, zipData: Data) async throws {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let payload: [String: Any] = ["ZipFile": zipData.base64EncodedString()]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.lambdaRequest(
            action: "UpdateFunctionCode",
            method: "PUT",
            path: "/functions/\(escaped)/code",
            body: body
        )
    }

    func deleteFunction(name: String) async throws {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        _ = try await client.lambdaRequest(
            action: "DeleteFunction",
            method: "DELETE",
            path: "/functions/\(escaped)"
        )
    }

    func invokeFunction(name: String, payload: String, invocationType: String = "RequestResponse") async throws -> LambdaInvocationResult {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let bodyData = payload.data(using: .utf8) ?? Data()
        let response = try await client.lambdaRequest(
            action: "Invoke",
            method: "POST",
            path: "/functions/\(escaped)/invocations",
            body: bodyData
        )

        let responsePayload = String(data: response.data, encoding: .utf8) ?? ""
        let functionError = response.headers["x-amz-function-error"]

        var logResult: String? = nil
        if let logBase64 = response.headers["x-amz-log-result"],
           let logData = Data(base64Encoded: logBase64),
           let decoded = String(data: logData, encoding: .utf8) {
            logResult = decoded
        }

        return LambdaInvocationResult(
            statusCode: 200,
            payload: responsePayload,
            functionError: functionError,
            logResult: logResult
        )
    }
}
