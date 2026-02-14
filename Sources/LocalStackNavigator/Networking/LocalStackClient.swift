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

    // MARK: - SNS (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for SNS actions — these are safe even though they use POST.
    private static let snsReadActions: Set<String> = [
        "ListTopics", "GetTopicAttributes", "ListSubscriptionsByTopic",
        "GetSubscriptionAttributes", "ListSubscriptions",
    ]

    /// Characters safe in form URL encoding (RFC 3986 unreserved).
    private static let formURLAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    func snsRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.snsReadActions.contains(action) {
            Log.warn("Blocked SNS \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "SNS:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        let bodyString = allParams
            .sorted { $0.key < $1.key }
            .map {
                let key = $0.key.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.key
                let val = $0.value.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.value
                return "\(key)=\(val)"
            }
            .joined(separator: "&")
        let body = bodyString.data(using: .utf8)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/sns/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-www-form-urlencoded",
            headers: ["Authorization": auth],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - DynamoDB (JSON protocol)

    /// Read-only whitelist for DynamoDB actions — these are safe even though they use POST.
    private static let dynamodbReadActions: Set<String> = [
        "ListTables", "DescribeTable", "Scan", "Query", "GetItem",
        "DescribeTimeToLive", "ListTagsOfResource",
    ]

    func dynamodbRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.dynamodbReadActions.contains(action) {
            Log.warn("Blocked DynamoDB \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "DynamoDB:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/dynamodb/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            headers: [
                "X-Amz-Target": "DynamoDB_20120810.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Secrets Manager (JSON protocol)

    /// Read-only whitelist for Secrets Manager actions — these are safe even though they use POST.
    private static let secretsManagerReadActions: Set<String> = [
        "ListSecrets", "DescribeSecret", "GetSecretValue",
    ]

    func secretsManagerRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.secretsManagerReadActions.contains(action) {
            Log.warn("Blocked SecretsManager \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "SecretsManager:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/secretsmanager/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "secretsmanager.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - SSM Parameter Store (JSON protocol)

    /// Read-only whitelist for SSM actions — these are safe even though they use POST.
    private static let ssmReadActions: Set<String> = [
        "DescribeParameters", "GetParameter", "GetParameters",
        "GetParametersByPath", "ListTagsForResource",
    ]

    func ssmRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.ssmReadActions.contains(action) {
            Log.warn("Blocked SSM \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "SSM:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/ssm/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "AmazonSSM.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - CloudWatch Logs (JSON protocol)

    /// Read-only whitelist for CloudWatch Logs actions — these are safe even though they use POST.
    private static let cloudWatchLogsReadActions: Set<String> = [
        "DescribeLogGroups", "DescribeLogStreams", "GetLogEvents", "FilterLogEvents",
    ]

    func cloudWatchLogsRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.cloudWatchLogsReadActions.contains(action) {
            Log.warn("Blocked CloudWatchLogs \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "CloudWatchLogs:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/logs/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "Logs_20140328.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - EventBridge (JSON protocol)

    /// Read-only whitelist for EventBridge actions — these are safe even though they use POST.
    private static let eventBridgeReadActions: Set<String> = [
        "ListEventBuses", "ListRules", "DescribeRule", "ListTargetsByRule", "ListTagsForResource",
    ]

    func eventBridgeRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.eventBridgeReadActions.contains(action) {
            Log.warn("Blocked EventBridge \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "EventBridge:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/events/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "AWSEvents.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Lambda (REST API)

    /// Read-only whitelist for Lambda actions — Invoke is allowed (runs function but doesn't modify config).
    private static let lambdaReadActions: Set<String> = [
        "ListFunctions", "GetFunction", "GetFunctionConfiguration", "Invoke",
    ]

    func lambdaRequest(
        action: String,
        method: String,
        path: String,
        body: Data? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.lambdaReadActions.contains(action) {
            Log.warn("Blocked Lambda \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Lambda:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/lambda/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        var headers = ["Authorization": auth]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        return try await executeRequest(
            method: method,
            path: "/2015-03-31" + path,
            queryParams: [:],
            body: body,
            contentType: body != nil ? "application/json" : nil,
            headers: headers,
            skipReadOnlyCheck: true
        )
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
