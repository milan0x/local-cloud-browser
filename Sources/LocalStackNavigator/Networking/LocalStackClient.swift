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

    // MARK: - SES (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for SES actions — these are safe even though they use POST.
    private static let sesReadActions: Set<String> = [
        "ListIdentities", "GetIdentityVerificationAttributes",
    ]

    func sesRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.sesReadActions.contains(action) {
            Log.warn("Blocked SES \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "SES:\(action)")
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
        let credential = "nav/\(dateStr)/\(appState.region)/ses/aws4_request"
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

    // MARK: - DynamoDB Streams (JSON protocol)

    func dynamodbStreamsRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
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
                "X-Amz-Target": "DynamoDBStreams_20120810.\(action)",
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

    // MARK: - EventBridge Scheduler (JSON protocol)

    /// Read-only whitelist for EventBridge Scheduler actions — these are safe even though they use POST.
    private static let schedulerReadActions: Set<String> = [
        "ListScheduleGroups", "GetScheduleGroup", "ListSchedules", "GetSchedule",
    ]

    func schedulerRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.schedulerReadActions.contains(action) {
            Log.warn("Blocked Scheduler \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Scheduler:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/scheduler/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "AWSScheduler.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - IAM (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for IAM actions — these are safe even though they use POST.
    private static let iamReadActions: Set<String> = [
        "ListUsers", "GetUser", "ListRoles", "GetRole",
        "ListPolicies", "GetPolicy", "GetPolicyVersion", "ListPolicyVersions",
        "ListAttachedUserPolicies", "ListAttachedRolePolicies", "ListAttachedGroupPolicies",
        "ListGroupsForUser", "ListGroups", "GetGroup",
    ]

    func iamRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.iamReadActions.contains(action) {
            Log.warn("Blocked IAM \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "IAM:\(action)")
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
        let credential = "nav/\(dateStr)/\(appState.region)/iam/aws4_request"
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

    // MARK: - CloudFormation (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for CloudFormation actions — these are safe even though they use POST.
    private static let cloudFormationReadActions: Set<String> = [
        "ListStacks", "DescribeStacks", "DescribeStackResources",
        "ListStackResources", "DescribeStackEvents", "GetTemplate",
    ]

    func cloudFormationRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.cloudFormationReadActions.contains(action) {
            Log.warn("Blocked CloudFormation \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "CloudFormation:\(action)")
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
        let credential = "nav/\(dateStr)/\(appState.region)/cloudformation/aws4_request"
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

    // MARK: - API Gateway (REST API)

    /// Read-only whitelist for API Gateway actions — safe read operations.
    private static let apiGatewayReadActions: Set<String> = [
        "GetRestApis", "GetRestApi", "GetResources", "GetResource",
        "GetMethod", "GetIntegration", "GetDeployments", "GetDeployment",
        "GetStages", "GetStage",
    ]

    func apiGatewayRequest(
        action: String,
        method: String,
        path: String,
        body: Data? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.apiGatewayReadActions.contains(action) {
            Log.warn("Blocked APIGateway \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "APIGateway:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/apigateway/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        var headers = ["Authorization": auth]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        return try await executeRequest(
            method: method,
            path: "/restapis" + path,
            queryParams: [:],
            body: body,
            contentType: body != nil ? "application/json" : nil,
            headers: headers,
            skipReadOnlyCheck: true
        )
    }

    // MARK: - ACM (JSON protocol)

    /// Read-only whitelist for ACM actions — these are safe even though they use POST.
    private static let acmReadActions: Set<String> = [
        "ListCertificates", "DescribeCertificate", "GetCertificate", "ListTagsForCertificate",
    ]

    func acmRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.acmReadActions.contains(action) {
            Log.warn("Blocked ACM \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "ACM:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/acm/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "CertificateManager.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Kinesis (JSON protocol)

    /// Read-only whitelist for Kinesis actions — these are safe even though they use POST.
    private static let kinesisReadActions: Set<String> = [
        "ListStreams", "DescribeStream", "DescribeStreamSummary",
        "ListShards", "GetShardIterator", "GetRecords", "ListTagsForStream",
    ]

    func kinesisRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.kinesisReadActions.contains(action) {
            Log.warn("Blocked Kinesis \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Kinesis:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/kinesis/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "Kinesis_20131202.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Kinesis Firehose (JSON protocol)

    /// Read-only whitelist for Kinesis Firehose actions — these are safe even though they use POST.
    private static let firehoseReadActions: Set<String> = [
        "ListDeliveryStreams", "DescribeDeliveryStream",
    ]

    func firehoseRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.firehoseReadActions.contains(action) {
            Log.warn("Blocked Firehose \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Firehose:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/firehose/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "Firehose_20150804.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - KMS (JSON protocol)

    /// Read-only whitelist for KMS actions — these are safe even though they use POST.
    private static let kmsReadActions: Set<String> = [
        "ListKeys", "DescribeKey", "GetKeyPolicy", "ListAliases",
    ]

    func kmsRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.kmsReadActions.contains(action) {
            Log.warn("Blocked KMS \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "KMS:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/kms/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "TrentService.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - CloudWatch (JSON protocol)

    /// Read-only whitelist for CloudWatch actions — these are safe even though they use POST.
    private static let cloudWatchReadActions: Set<String> = [
        "ListMetrics", "GetMetricStatistics", "GetMetricData", "DescribeAlarms", "DescribeAlarmsForMetric",
    ]

    func cloudWatchRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.cloudWatchReadActions.contains(action) {
            Log.warn("Blocked CloudWatch \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "CloudWatch:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/monitoring/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            headers: [
                "X-Amz-Target": "GraniteServiceVersion20100801.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Route 53 Resolver (JSON protocol)

    /// Read-only whitelist for Route 53 Resolver actions — these are safe even though they use POST.
    private static let route53ResolverReadActions: Set<String> = [
        "ListResolverEndpoints", "GetResolverEndpoint",
        "ListResolverEndpointIpAddresses",
        "ListResolverRules", "GetResolverRule",
        "ListResolverRuleAssociations", "GetResolverRuleAssociation",
        "ListTagsForResource",
    ]

    func route53ResolverRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.route53ResolverReadActions.contains(action) {
            Log.warn("Blocked Route53Resolver \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Route53Resolver:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/route53resolver/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "Route53Resolver.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Route 53 (REST API with XML)

    func route53Request(
        method: String,
        path: String,
        body: Data? = nil
    ) async throws -> Data {
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/route53/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: method,
            path: "/2013-04-01" + path,
            queryParams: [:],
            body: body,
            contentType: body != nil ? "application/xml" : nil,
            headers: ["Authorization": auth]
        )
        return response.data
    }

    // MARK: - Redshift (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for Redshift actions — these are safe even though they use POST.
    private static let redshiftReadActions: Set<String> = [
        "DescribeClusters",
    ]

    func redshiftRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.redshiftReadActions.contains(action) {
            Log.warn("Blocked Redshift \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "Redshift:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        allParams["Version"] = "2012-12-01"
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
        let credential = "nav/\(dateStr)/\(appState.region)/redshift/aws4_request"
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

    // MARK: - OpenSearch (REST API)

    /// Read-only whitelist for OpenSearch actions — safe read operations.
    private static let opensearchReadActions: Set<String> = [
        "ListDomainNames", "DescribeDomain",
    ]

    func opensearchRequest(
        action: String,
        method: String,
        path: String,
        body: Data? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.opensearchReadActions.contains(action) {
            Log.warn("Blocked OpenSearch \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "OpenSearch:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/es/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        var headers = ["Authorization": auth]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        return try await executeRequest(
            method: method,
            path: "/2021-01-01" + path,
            queryParams: [:],
            body: body,
            contentType: body != nil ? "application/json" : nil,
            headers: headers,
            skipReadOnlyCheck: true
        )
    }

    // MARK: - EC2 (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for EC2 actions — these are safe even though they use POST.
    private static let ec2ReadActions: Set<String> = [
        "DescribeInstances", "DescribeSecurityGroups", "DescribeKeyPairs",
        "DescribeVpcs", "DescribeSubnets", "DescribeImages",
    ]

    func ec2Request(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.ec2ReadActions.contains(action) {
            Log.warn("Blocked EC2 \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "EC2:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        allParams["Version"] = "2016-11-15"
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
        let credential = "nav/\(dateStr)/\(appState.region)/ec2/aws4_request"
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

    // MARK: - Step Functions (JSON protocol)

    /// Read-only whitelist for Step Functions actions — these are safe even though they use POST.
    private static let stepFunctionsReadActions: Set<String> = [
        "ListStateMachines", "DescribeStateMachine", "ListExecutions",
        "DescribeExecution", "GetExecutionHistory",
    ]

    func stepFunctionsRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.stepFunctionsReadActions.contains(action) {
            Log.warn("Blocked StepFunctions \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "StepFunctions:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(appState.region)/states/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            headers: [
                "X-Amz-Target": "AWSStepFunctions.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - STS (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for STS actions — these are safe even though they use POST.
    private static let stsReadActions: Set<String> = [
        "GetCallerIdentity",
    ]

    func stsRequest(action: String, params: [String: String] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.stsReadActions.contains(action) {
            Log.warn("Blocked STS \(action) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: "STS:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        allParams["Version"] = "2011-06-15"
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
        let credential = "nav/\(dateStr)/\(appState.region)/sts/aws4_request"
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
