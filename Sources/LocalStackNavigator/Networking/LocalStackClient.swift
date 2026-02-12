import Foundation

enum LocalStackClientError: Error, LocalizedError {
    case invalidURL
    case readOnlyBlocked(method: String)
    case httpError(statusCode: Int, data: Data)
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .readOnlyBlocked(let method):
            "Blocked \(method) request — read-only mode is enabled"
        case .httpError(let statusCode, let data):
            if let parsed = ServiceError.parse(from: data) {
                "\(parsed.code): \(parsed.message)"
            } else {
                "HTTP error \(statusCode)"
            }
        case .networkError(let underlying):
            "Network error: \(underlying.localizedDescription)\n\nCheck that your Docker container is running and the LocalStack endpoint is reachable."
        }
    }

    /// Extracts a structured `ServiceError` from the XML body of an HTTP error response.
    var serviceError: ServiceError? {
        guard case .httpError(_, let data) = self else { return nil }
        return ServiceError.parse(from: data)
    }
}

struct HTTPResponse {
    let data: Data
    let headers: [String: String]
}

@MainActor
final class LocalStackClient: ObservableObject {
    private let session: URLSession
    private let appState: AppState

    init(appState: AppState, session: URLSession = .shared) {
        self.appState = appState
        self.session = session
    }

    var baseURL: String { appState.endpoint }

    /// S3 base URL using LocalStack's virtual-hosted-style routing.
    /// Rewrites `http://localhost:4566` → `http://s3.localhost.localstack.cloud:4566`.
    var s3BaseURL: String {
        guard let components = URLComponents(string: appState.endpoint),
              let host = components.host?.lowercased() else {
            return appState.endpoint
        }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard isLocal else { return appState.endpoint }
        var s3Components = components
        s3Components.host = "s3.localhost.localstack.cloud"
        return s3Components.string ?? appState.endpoint
    }

    func get(path: String) async throws -> Data {
        try await request(method: "GET", path: path)
    }

    func post(path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "POST", path: path, body: body)
    }

    func put(path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "PUT", path: path, body: body)
    }

    func delete(path: String) async throws -> Data {
        try await request(method: "DELETE", path: path)
    }

    func head(path: String) async throws -> [String: String] {
        let response = try await executeRequest(
            method: "HEAD",
            path: path,
            queryParams: [:],
            body: nil,
            contentType: nil
        )
        return response.headers
    }

    func request(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        let response = try await executeRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            body: body,
            contentType: contentType
        )
        return response.data
    }

    func requestWithHeaders(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> HTTPResponse {
        try await executeRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            body: body,
            contentType: contentType
        )
    }

    // MARK: - S3 (virtual-hosted-style routing)

    func s3Request(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let response = try await executeRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            body: body,
            contentType: contentType,
            baseURLOverride: s3BaseURL,
            headers: headers
        )
        return response.data
    }

    func s3Head(path: String) async throws -> [String: String] {
        let response = try await executeRequest(
            method: "HEAD",
            path: path,
            queryParams: [:],
            body: nil,
            contentType: nil,
            baseURLOverride: s3BaseURL
        )
        return response.headers
    }

    // MARK: - SQS (JSON protocol)

    /// Read-only whitelist for SQS actions — these are safe even though they use POST.
    private static let sqsReadActions: Set<String> = [
        "ListQueues", "GetQueueUrl", "GetQueueAttributes", "ReceiveMessage",
        "ListQueueTags", "ListDeadLetterSourceQueues",
    ]

    func sqsRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.sqsReadActions.contains(action) {
            Log.warn("Blocked SQS \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "SQS:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        // LocalStack uses the region from the SigV4 Authorization header to scope
        // SQS queries. We send a minimal (unsigned) credential so LocalStack knows
        // which region we're targeting. Signatures are not validated.
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/sqs/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            headers: [
                "X-Amz-Target": "AmazonSQS.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    private static let iso8601DateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func executeRequest(
        method: String,
        path: String,
        queryParams: [String: String],
        body: Data?,
        contentType: String?,
        baseURLOverride: String? = nil,
        headers: [String: String] = [:],
        skipReadOnlyCheck: Bool = false
    ) async throws -> HTTPResponse {
        let effectiveBase = baseURLOverride ?? baseURL

        guard skipReadOnlyCheck || ReadOnlyInterceptor.allowsRequest(method: method, isReadOnly: appState.isReadOnly) else {
            Log.warn("Blocked \(method) \(path) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: method)
        }

        guard var components = URLComponents(string: effectiveBase + path) else {
            Log.error("Invalid URL: \(effectiveBase + path)", category: "HTTP")
            throw LocalStackClientError.invalidURL
        }

        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            Log.error("Invalid URL components: \(components)", category: "HTTP")
            throw LocalStackClientError.invalidURL
        }

        Log.info("\(method) \(url.absoluteString)", category: "HTTP")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        if let contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        } else if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            Log.error("\(method) \(path) failed: \(error.localizedDescription)", category: "HTTP")
            throw LocalStackClientError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.error("\(method) \(path) — non-HTTP response", category: "HTTP")
            throw LocalStackClientError.invalidURL
        }

        Log.info("\(method) \(path) -> \(httpResponse.statusCode)", category: "HTTP")

        if (200..<300).contains(httpResponse.statusCode) {
            appState.notifyConnectionAlive()
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<binary>"
            Log.error("\(method) \(path) -> \(httpResponse.statusCode): \(bodyPreview)", category: "HTTP")
            throw LocalStackClientError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }

        return HTTPResponse(data: data, headers: headers)
    }
}
