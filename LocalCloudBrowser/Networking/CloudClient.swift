import Foundation

enum CloudClientError: Error, LocalizedError {
    case invalidURL
    case readOnlyBlocked(method: String)
    case httpError(statusCode: Int, data: Data, headers: [String: String] = [:])
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .readOnlyBlocked(let method):
            "Blocked \(method) request — read-only mode is enabled"
        case .httpError(let statusCode, let data, _):
            if let parsed = ServiceError.parse(from: data) {
                "\(parsed.code): \(parsed.message)"
            } else {
                "HTTP error \(statusCode)"
            }
        case .networkError(let underlying):
            "Network error: \(underlying.localizedDescription)\n\nCheck that your endpoint is running and reachable."
        }
    }

    /// Extracts a structured `ServiceError` from the XML body of an HTTP error response.
    var serviceError: ServiceError? {
        guard case .httpError(_, let data, _) = self else { return nil }
        return ServiceError.parse(from: data)
    }

    /// Whether this error is safe to retry (network errors + server-side 5xx).
    var isRetryable: Bool {
        switch self {
        case .networkError:
            return true
        case .httpError(let statusCode, _, _):
            return [500, 502, 503, 504].contains(statusCode)
        default:
            return false
        }
    }

    /// Extracts the correct region from a PermanentRedirect or
    /// AuthorizationHeaderMalformed error. S3 returns the bucket's region
    /// in the `x-amz-bucket-region` response header for cross-region
    /// requests, falling back to parsing the error message body.
    var redirectRegion: String? {
        guard case .httpError(let code, let data, let headers) = self,
              (code == 301 || code == 400 || code == 403) else { return nil }
        if let region = headers["x-amz-bucket-region"], !region.isEmpty {
            return region
        }
        let parsed = ServiceError.parse(from: data)
        guard parsed?.code == "PermanentRedirect" || parsed?.code == "AuthorizationHeaderMalformed" else {
            return nil
        }
        if let message = parsed?.message,
           let match = message.range(of: "expecting '"),
           let end = message[match.upperBound...].range(of: "'") {
            let region = String(message[match.upperBound..<end.lowerBound])
            if !region.isEmpty { return region }
        }
        return nil
    }
}

struct HTTPResponse {
    let data: Data
    let headers: [String: String]
}

@MainActor
final class CloudClient: ObservableObject {
    private let session: URLSession
    private let appState: AppState

    /// Exposed for streaming download/upload paths that build their own URLSession calls
    /// (e.g. S3Service.downloadObjectToFile, S3QuickLookManager) so they use the same
    /// session as all other CloudClient requests.
    var downloadSession: URLSession { session }

    init(appState: AppState, session: URLSession = .shared) {
        self.appState = appState
        self.session = session
    }

    var baseURL: String { appState.endpoint }

    var isLocalEndpoint: Bool { appState.isLocalEndpoint }

    /// S3 base URL using virtual-hosted-style routing.
    /// Rewrites `http://localhost:4566` → `http://<s3Domain>:4566`.
    var s3BaseURL: String {
        guard !appState.s3Domain.isEmpty,
              let components = URLComponents(string: appState.endpoint),
              components.host != nil else {
            return appState.endpoint
        }
        guard isLocalEndpoint else { return appState.endpoint }
        var s3Components = components
        s3Components.host = appState.s3Domain
        return s3Components.string ?? appState.endpoint
    }

    /// Creates a Sendable snapshot of current credentials for background uploads.
    /// Call this on the main thread, then pass the context to StreamingUploader.
    func makeSigningContext() -> RequestSigningContext {
        let isVirtualHosted: Bool
        if case .virtualHosted = s3URLStyle {
            isVirtualHosted = true
        } else {
            isVirtualHosted = false
        }
        return RequestSigningContext(
            endpoint: appState.endpoint,
            s3BaseURL: s3BaseURL,
            region: appState.region,
            accessKeyId: appState.accessKeyId,
            secretAccessKey: appState.secretAccessKey,
            sessionToken: appState.sessionToken,
            needsSigning: appState.needsSigning,
            isReadOnly: appState.isReadOnly,
            usesVirtualHostedStyle: isVirtualHosted
        )
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

    // MARK: - S3 URL routing

    enum S3URLStyle {
        case pathStyle(baseURL: String)
        case virtualHosted(region: String)
    }

    var s3URLStyle: S3URLStyle {
        s3URLStyle(regionOverride: nil)
    }

    func s3URLStyle(regionOverride: String?) -> S3URLStyle {
        if isLocalEndpoint {
            return .pathStyle(baseURL: s3BaseURL)
        }
        if let host = URLComponents(string: appState.endpoint)?.host?.lowercased(),
           host.contains("amazonaws.com") {
            return .virtualHosted(region: regionOverride ?? appState.region)
        }
        return .pathStyle(baseURL: appState.endpoint)
    }

    /// Resolves the S3 base URL and object path for a given request path.
    /// For virtual-hosted-style, extracts the bucket from the path and moves it to the hostname.
    /// - Parameters:
    ///   - path: Always in format `/bucket/key` or `/` for listBuckets.
    ///   - regionOverride: If provided, overrides `appState.region` for this
    ///     call — used when auto-detecting that a bucket lives in a different
    ///     region than the connection's default.
    private func resolveS3URL(path: String, regionOverride: String? = nil) -> (baseURL: String, objectPath: String) {
        switch s3URLStyle(regionOverride: regionOverride) {
        case .pathStyle(let baseURL):
            return (baseURL, path)
        case .virtualHosted(let region):
            // Split "/bucket/key/path" into bucket and the rest
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let components = trimmed.split(separator: "/", maxSplits: 1)

            if components.isEmpty {
                // Root path — listBuckets: https://s3.region.amazonaws.com/
                return ("https://s3.\(region).amazonaws.com", "/")
            }

            let bucket = String(components[0])
            let objectPath = components.count > 1 ? "/\(components[1])" : "/"
            return ("https://\(bucket).s3.\(region).amazonaws.com", objectPath)
        }
    }

    func s3Request(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        unsignedPayload: Bool = false,
        regionOverride: String? = nil
    ) async throws -> Data {
        let (baseURL, objectPath) = resolveS3URL(path: path, regionOverride: regionOverride)
        let response = try await executeRequest(
            method: method,
            path: objectPath,
            queryParams: queryParams,
            body: body,
            contentType: contentType,
            baseURLOverride: baseURL,
            headers: headers,
            service: "s3",
            unsignedPayload: unsignedPayload,
            signingRegion: regionOverride
        )
        return response.data
    }

    func s3RequestWithHeaders(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        unsignedPayload: Bool = false,
        regionOverride: String? = nil
    ) async throws -> HTTPResponse {
        let (baseURL, objectPath) = resolveS3URL(path: path, regionOverride: regionOverride)
        return try await executeRequest(
            method: method,
            path: objectPath,
            queryParams: queryParams,
            body: body,
            contentType: contentType,
            baseURLOverride: baseURL,
            headers: headers,
            service: "s3",
            unsignedPayload: unsignedPayload,
            signingRegion: regionOverride
        )
    }

    func s3Head(path: String) async throws -> [String: String] {
        let (baseURL, objectPath) = resolveS3URL(path: path)
        let response = try await executeRequest(
            method: "HEAD",
            path: objectPath,
            queryParams: [:],
            body: nil,
            contentType: nil,
            baseURLOverride: baseURL,
            service: "s3"
        )
        return response.headers
    }

    // MARK: - SQS (JSON protocol)

    /// Read-only whitelist for SQS actions — these are safe even though they use POST.
    private static let sqsReadActions: Set<String> = [
        "ListQueues", "GetQueueUrl", "GetQueueAttributes", "ReceiveMessage",
        "ListQueueTags", "ListDeadLetterSourceQueues",
    ]

    func sqsRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.sqsReadActions.contains(action) {
            Log.warn("Blocked SQS \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "SQS:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "sqs", region: region)
        var headers: [String: String] = ["X-Amz-Target": "AmazonSQS.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
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

    func snsRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.snsReadActions.contains(action) {
            Log.warn("Blocked SNS \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "SNS:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        allParams["Version"] = "2010-03-31"
        let bodyString = allParams
            .sorted { $0.key < $1.key }
            .map {
                let key = $0.key.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.key
                let val = $0.value.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.value
                return "\(key)=\(val)"
            }
            .joined(separator: "&")
        let body = bodyString.data(using: .utf8)
        let plan = awsEndpoint(service: "sns", region: region)
        var headers: [String: String] = [:]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-www-form-urlencoded",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - SES (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for SES actions — these are safe even though they use POST.
    private static let sesReadActions: Set<String> = [
        "ListIdentities", "GetIdentityVerificationAttributes",
    ]

    func sesRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.sesReadActions.contains(action) {
            Log.warn("Blocked SES \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "SES:\(action)")
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
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/ses/aws4_request"
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

    func dynamodbRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.dynamodbReadActions.contains(action) {
            Log.warn("Blocked DynamoDB \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "DynamoDB:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "dynamodb", region: region)
        var headers: [String: String] = ["X-Amz-Target": "DynamoDB_20120810.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - DynamoDB Streams (JSON protocol)

    /// Read-only whitelist for DynamoDB Streams actions — all are inherently read-only.
    private static let dynamodbStreamsReadActions: Set<String> = [
        "ListStreams", "DescribeStream", "GetShardIterator", "GetRecords",
    ]

    func dynamodbStreamsRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.dynamodbStreamsReadActions.contains(action) {
            Log.warn("Blocked DynamoDB Streams \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "DynamoDBStreams:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let hostname = "https://streams.dynamodb.\(effectiveRegion(region)).amazonaws.com"
        let plan = awsEndpoint(service: "dynamodb", region: region, hostnameOverride: hostname)
        var headers: [String: String] = ["X-Amz-Target": "DynamoDBStreams_20120810.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - Secrets Manager (JSON protocol)

    /// Read-only whitelist for Secrets Manager actions — these are safe even though they use POST.
    private static let secretsManagerReadActions: Set<String> = [
        "ListSecrets", "DescribeSecret", "GetSecretValue",
    ]

    func secretsManagerRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.secretsManagerReadActions.contains(action) {
            Log.warn("Blocked SecretsManager \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "SecretsManager:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "secretsmanager", region: region)
        var headers: [String: String] = ["X-Amz-Target": "secretsmanager.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - SSM Parameter Store (JSON protocol)

    /// Read-only whitelist for SSM actions — these are safe even though they use POST.
    private static let ssmReadActions: Set<String> = [
        "DescribeParameters", "GetParameter", "GetParameters",
        "GetParametersByPath", "ListTagsForResource",
    ]

    func ssmRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.ssmReadActions.contains(action) {
            Log.warn("Blocked SSM \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "SSM:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "ssm", region: region)
        var headers: [String: String] = ["X-Amz-Target": "AmazonSSM.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - CloudWatch Logs (JSON protocol)

    /// Read-only whitelist for CloudWatch Logs actions — these are safe even though they use POST.
    private static let cloudWatchLogsReadActions: Set<String> = [
        "DescribeLogGroups", "DescribeLogStreams", "GetLogEvents", "FilterLogEvents",
    ]

    func cloudWatchLogsRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.cloudWatchLogsReadActions.contains(action) {
            Log.warn("Blocked CloudWatchLogs \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "CloudWatchLogs:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "logs", region: region)
        var headers: [String: String] = ["X-Amz-Target": "Logs_20140328.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - EventBridge (JSON protocol)

    /// Read-only whitelist for EventBridge actions — these are safe even though they use POST.
    private static let eventBridgeReadActions: Set<String> = [
        "ListEventBuses", "ListRules", "DescribeRule", "ListTargetsByRule", "ListTagsForResource",
    ]

    func eventBridgeRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.eventBridgeReadActions.contains(action) {
            Log.warn("Blocked EventBridge \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "EventBridge:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "events", region: region)
        var headers: [String: String] = ["X-Amz-Target": "AWSEvents.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - EventBridge Scheduler (JSON protocol)

    /// Read-only whitelist for EventBridge Scheduler actions — these are safe even though they use POST.
    private static let schedulerReadActions: Set<String> = [
        "ListScheduleGroups", "GetScheduleGroup", "ListSchedules", "GetSchedule",
    ]

    func schedulerRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.schedulerReadActions.contains(action) {
            Log.warn("Blocked Scheduler \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Scheduler:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "scheduler", region: region)
        var headers: [String: String] = ["X-Amz-Target": "AWSScheduler.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
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

    func iamRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.iamReadActions.contains(action) {
            Log.warn("Blocked IAM \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "IAM:\(action)")
        }
        var allParams = params
        allParams["Action"] = action
        allParams["Version"] = "2010-05-08"
        let bodyString = allParams
            .sorted { $0.key < $1.key }
            .map {
                let key = $0.key.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.key
                let val = $0.value.addingPercentEncoding(withAllowedCharacters: Self.formURLAllowed) ?? $0.value
                return "\(key)=\(val)"
            }
            .joined(separator: "&")
        let body = bodyString.data(using: .utf8)
        // IAM is a global service — real AWS uses iam.amazonaws.com and SigV4 region us-east-1,
        // regardless of the user's selected region.
        let plan = awsEndpoint(
            service: "iam",
            region: region,
            hostnameOverride: "https://iam.amazonaws.com",
            signingRegionOverride: "us-east-1"
        )
        var headers: [String: String] = [:]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-www-form-urlencoded",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - CloudFormation (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for CloudFormation actions — these are safe even though they use POST.
    private static let cloudFormationReadActions: Set<String> = [
        "ListStacks", "DescribeStacks", "DescribeStackResources",
        "ListStackResources", "DescribeStackEvents", "GetTemplate",
    ]

    func cloudFormationRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.cloudFormationReadActions.contains(action) {
            Log.warn("Blocked CloudFormation \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "CloudFormation:\(action)")
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
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/cloudformation/aws4_request"
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
        body: Data? = nil,
        region: String? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.apiGatewayReadActions.contains(action) {
            Log.warn("Blocked APIGateway \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "APIGateway:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/apigateway/aws4_request"
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

    func acmRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.acmReadActions.contains(action) {
            Log.warn("Blocked ACM \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "ACM:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "acm", region: region)
        var headers: [String: String] = ["X-Amz-Target": "CertificateManager.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - Kinesis (JSON protocol)

    /// Read-only whitelist for Kinesis actions — these are safe even though they use POST.
    private static let kinesisReadActions: Set<String> = [
        "ListStreams", "DescribeStream", "DescribeStreamSummary",
        "ListShards", "GetShardIterator", "GetRecords", "ListTagsForStream",
    ]

    func kinesisRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.kinesisReadActions.contains(action) {
            Log.warn("Blocked Kinesis \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Kinesis:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "kinesis", region: region)
        var headers: [String: String] = ["X-Amz-Target": "Kinesis_20131202.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - Kinesis Firehose (JSON protocol)

    /// Read-only whitelist for Kinesis Firehose actions — these are safe even though they use POST.
    private static let firehoseReadActions: Set<String> = [
        "ListDeliveryStreams", "DescribeDeliveryStream",
    ]

    func firehoseRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.firehoseReadActions.contains(action) {
            Log.warn("Blocked Firehose \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Firehose:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "firehose", region: region)
        var headers: [String: String] = ["X-Amz-Target": "Firehose_20150804.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - KMS (JSON protocol)

    /// Read-only whitelist for KMS actions — these are safe even though they use POST.
    private static let kmsReadActions: Set<String> = [
        "ListKeys", "DescribeKey", "GetKeyPolicy", "ListAliases",
    ]

    func kmsRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.kmsReadActions.contains(action) {
            Log.warn("Blocked KMS \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "KMS:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "kms", region: region)
        var headers: [String: String] = ["X-Amz-Target": "TrentService.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - CloudWatch (JSON protocol)

    /// Read-only whitelist for CloudWatch actions — these are safe even though they use POST.
    private static let cloudWatchReadActions: Set<String> = [
        "ListMetrics", "GetMetricStatistics", "GetMetricData", "DescribeAlarms", "DescribeAlarmsForMetric",
    ]

    func cloudWatchRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.cloudWatchReadActions.contains(action) {
            Log.warn("Blocked CloudWatch \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "CloudWatch:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "monitoring", region: region)
        var headers: [String: String] = ["X-Amz-Target": "GraniteServiceVersion20100801.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
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

    func route53ResolverRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.route53ResolverReadActions.contains(action) {
            Log.warn("Blocked Route53Resolver \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Route53Resolver:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/route53resolver/aws4_request"
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

    private static let route53ReadMethods: Set<String> = ["GET", "HEAD"]

    func route53Request(
        method: String,
        path: String,
        body: Data? = nil,
        region: String? = nil
    ) async throws -> Data {
        if appState.isReadOnly && !Self.route53ReadMethods.contains(method.uppercased()) {
            Log.warn("Blocked Route53 \(method) \(path) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Route53:\(method)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/route53/aws4_request"
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

    func redshiftRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.redshiftReadActions.contains(action) {
            Log.warn("Blocked Redshift \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Redshift:\(action)")
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
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/redshift/aws4_request"
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
        body: Data? = nil,
        region: String? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.opensearchReadActions.contains(action) {
            Log.warn("Blocked OpenSearch \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "OpenSearch:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/es/aws4_request"
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

    func ec2Request(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.ec2ReadActions.contains(action) {
            Log.warn("Blocked EC2 \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "EC2:\(action)")
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
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/ec2/aws4_request"
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

    func stepFunctionsRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.stepFunctionsReadActions.contains(action) {
            Log.warn("Blocked StepFunctions \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "StepFunctions:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let plan = awsEndpoint(service: "states", region: region)
        var headers: [String: String] = ["X-Amz-Target": "AWSStepFunctions.\(action)"]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.0",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
        )
        return response.data
    }

    // MARK: - STS (Query protocol — form-encoded POST with Action= parameter)

    /// Read-only whitelist for STS actions — these are safe even though they use POST.
    private static let stsReadActions: Set<String> = [
        "GetCallerIdentity",
    ]

    func stsRequest(action: String, params: [String: String] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.stsReadActions.contains(action) {
            Log.warn("Blocked STS \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "STS:\(action)")
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
        let plan = awsEndpoint(service: "sts", region: region)
        var headers: [String: String] = [:]
        if let auth = plan.authHeader { headers["Authorization"] = auth }
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-www-form-urlencoded",
            baseURLOverride: plan.baseURL,
            headers: headers,
            skipReadOnlyCheck: true,
            service: plan.signingService,
            signingRegion: plan.signingRegion
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
        body: Data? = nil,
        region: String? = nil
    ) async throws -> HTTPResponse {
        if appState.isReadOnly && !Self.lambdaReadActions.contains(action) {
            Log.warn("Blocked Lambda \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Lambda:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/lambda/aws4_request"
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

    // MARK: - Resource Groups (REST-JSON protocol)

    /// Read-only whitelist for Resource Groups actions — safe read operations.
    private static let resourceGroupsReadActions: Set<String> = [
        "ListGroups", "GetGroup", "GetGroupQuery", "ListGroupResources", "SearchResources",
    ]

    func resourceGroupsRequest(
        action: String,
        method: String,
        path: String,
        body: Data? = nil,
        region: String? = nil
    ) async throws -> Data {
        if appState.isReadOnly && !Self.resourceGroupsReadActions.contains(action) {
            Log.warn("Blocked ResourceGroups \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "ResourceGroups:\(action)")
        }
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/resource-groups/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        var headers = ["Authorization": auth]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }
        let response = try await executeRequest(
            method: method,
            path: path,
            queryParams: [:],
            body: body,
            contentType: body != nil ? "application/json" : nil,
            headers: headers,
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Config (JSON 1.1 protocol)

    /// Read-only whitelist for Config actions — these are safe even though they use POST.
    private static let configReadActions: Set<String> = [
        "DescribeConfigurationRecorders", "DescribeConfigurationRecorderStatus",
        "DescribeDeliveryChannels", "DescribeDeliveryChannelStatus",
    ]

    func configRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.configReadActions.contains(action) {
            Log.warn("Blocked Config \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Config:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/config/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "StarlingDoveService.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Support (JSON 1.1 protocol)

    /// Read-only whitelist for Support actions — these are safe even though they use POST.
    private static let supportReadActions: Set<String> = [
        "DescribeCases", "DescribeServices", "DescribeSeverityLevels", "DescribeCommunications",
    ]

    func supportRequest(action: String, payload: [String: Any] = [:]) async throws -> Data {
        if appState.isReadOnly && !Self.supportReadActions.contains(action) {
            Log.warn("Blocked Support \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Support:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/us-east-1/support/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "AWSSupport_20130415.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    // MARK: - Transcribe (JSON 1.1 protocol)

    /// Read-only whitelist for Transcribe actions — these are safe even though they use POST.
    private static let transcribeReadActions: Set<String> = [
        "ListTranscriptionJobs", "GetTranscriptionJob",
    ]

    func transcribeRequest(action: String, payload: [String: Any] = [:], region: String? = nil) async throws -> Data {
        if appState.isReadOnly && !Self.transcribeReadActions.contains(action) {
            Log.warn("Blocked Transcribe \(action) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: "Transcribe:\(action)")
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let dateStr = Self.iso8601DateOnly.string(from: Date())
        let credential = "nav/\(dateStr)/\(effectiveRegion(region))/transcribe/aws4_request"
        let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
        let response = try await executeRequest(
            method: "POST",
            path: "/",
            queryParams: [:],
            body: body,
            contentType: "application/x-amz-json-1.1",
            headers: [
                "X-Amz-Target": "Transcribe.\(action)",
                "Authorization": auth,
            ],
            skipReadOnlyCheck: true
        )
        return response.data
    }

    private func effectiveRegion(_ override: String?) -> String {
        override ?? appState.region
    }

    // MARK: - AWS service endpoint routing

    /// Describes how a service request should be dispatched:
    /// - For production (signing) connections: a regional AWS hostname and SigV4 routing.
    /// - For LocalStack/local connections: no hostname override and a minimal unsigned
    ///   credential header so the endpoint can parse the region from the auth line.
    private struct AWSEndpointPlan {
        let baseURL: String?        // nil → use appState.endpoint
        let authHeader: String?     // pre-set Authorization header (LocalStack path only)
        let signingService: String? // when non-nil, buildURLRequest runs SigV4Signer
        let signingRegion: String?  // override signing region (e.g., IAM → us-east-1)
    }

    /// Resolves routing + auth posture for an AWS service request.
    /// Defaults to `https://{service}.{region}.amazonaws.com`. Supply
    /// `hostnameOverride` for services with a non-standard hostname (IAM global,
    /// streams.dynamodb, etc.). Supply `signingRegionOverride` when SigV4 must
    /// use a fixed region regardless of the user's selected region (IAM).
    private func awsEndpoint(
        service: String,
        region: String? = nil,
        hostnameOverride: String? = nil,
        signingRegionOverride: String? = nil
    ) -> AWSEndpointPlan {
        let callerRegion = effectiveRegion(region)
        if appState.needsSigning {
            let hostname = hostnameOverride ?? "https://\(service).\(callerRegion).amazonaws.com"
            return AWSEndpointPlan(
                baseURL: hostname,
                authHeader: nil,
                signingService: service,
                signingRegion: signingRegionOverride
            )
        } else {
            let dateStr = Self.iso8601DateOnly.string(from: Date())
            let credentialRegion = signingRegionOverride ?? callerRegion
            let credential = "nav/\(dateStr)/\(credentialRegion)/\(service)/aws4_request"
            let auth = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host, Signature=unsigned"
            return AWSEndpointPlan(
                baseURL: nil,
                authHeader: auth,
                signingService: nil,
                signingRegion: nil
            )
        }
    }

    private static let iso8601DateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Caller identity

    /// Fetches the current STS caller identity and stores it on AppState.
    /// Used by the permission-denied helper to pre-fill the user's name in CLI commands.
    /// Silent on failure — identity is a nice-to-have, never blocks UI.
    func fetchCallerIdentity() async {
        do {
            let data = try await stsRequest(action: "GetCallerIdentity")
            let xml = try SNSXMLParser.parse(data)
            let identity = CallerIdentity(
                account: xml.first("Account") ?? "",
                arn: xml.first("Arn") ?? "",
                userId: xml.first("UserId") ?? ""
            )
            appState.callerIdentity = identity
            Log.info("Caller identity: \(identity.arn)", category: "App")
        } catch {
            Log.warn("Failed to fetch caller identity: \(error.localizedDescription)", category: "App")
        }
    }

    // MARK: - Permission detection

    /// Calls IAM SimulatePrincipalPolicy to check which of the given actions
    /// the caller is allowed to perform. Returns the set of allowed actions.
    /// Throws on any error. Caller should handle failure silently —
    /// detection is a nice-to-have.
    func simulatePrincipalPolicy(principal: String, actions: [String]) async throws -> Set<String> {
        guard !actions.isEmpty else { return [] }
        var params: [String: String] = [
            "PolicySourceArn": principal,
        ]
        for (i, action) in actions.enumerated() {
            params["ActionNames.member.\(i + 1)"] = action
        }
        let data = try await iamRequest(action: "SimulatePrincipalPolicy", params: params)
        return Self.parseSimulateResponse(data)
    }

    /// Extracts the set of allowed actions from a SimulatePrincipalPolicy
    /// XML response body.
    private static func parseSimulateResponse(_ data: Data) -> Set<String> {
        SimulatePolicyXMLParser(data: data).parse()
    }

    /// Finds inline policies attached to the user that contain a `Deny`
    /// statement matching the given service prefix (e.g., "s3", "sqs").
    /// Used by the permission helper to surface exact cleanup commands.
    /// Silent on failure (missing IAM permissions, etc.) — returns [].
    func findInlineDeniesForService(userName: String, servicePrefix: String) async -> [String] {
        do {
            let listData = try await iamRequest(
                action: "ListUserPolicies",
                params: ["UserName": userName]
            )
            let names = ListUserPoliciesXMLParser(data: listData).parse()

            var denyingNames: [String] = []
            for name in names {
                do {
                    let getData = try await iamRequest(
                        action: "GetUserPolicy",
                        params: ["UserName": userName, "PolicyName": name]
                    )
                    if Self.policyDocumentDeniesService(getData, prefix: servicePrefix) {
                        denyingNames.append(name)
                    }
                } catch {
                    continue
                }
            }
            return denyingNames
        } catch {
            Log.warn("Inline-deny detection failed: \(error.localizedDescription)", category: "App")
            return []
        }
    }

    /// Returns true if the GetUserPolicy response's policy document contains
    /// a Deny statement that would block actions matching the service prefix.
    private static func policyDocumentDeniesService(_ data: Data, prefix: String) -> Bool {
        guard let policyJSON = GetUserPolicyXMLParser(data: data).parse(),
              let decoded = policyJSON.removingPercentEncoding?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            return false
        }

        let statements: [[String: Any]]
        if let arr = root["Statement"] as? [[String: Any]] {
            statements = arr
        } else if let single = root["Statement"] as? [String: Any] {
            statements = [single]
        } else {
            return false
        }

        for stmt in statements {
            guard (stmt["Effect"] as? String) == "Deny" else { continue }
            let actions: [String]
            if let arr = stmt["Action"] as? [String] {
                actions = arr
            } else if let single = stmt["Action"] as? String {
                actions = [single]
            } else {
                continue
            }
            for action in actions {
                if action == "*" { return true }
                if action == "\(prefix):*" { return true }
                if action.hasPrefix("\(prefix):") { return true }
            }
        }
        return false
    }

    // MARK: - Request building

    /// Builds a signed URLRequest without executing it.
    /// Used by streaming download paths that need SigV4 signatures but use URLSession.download.
    func buildSignedS3Request(
        method: String,
        path: String,
        queryParams: [String: String] = [:]
    ) throws -> URLRequest {
        let (baseURL, objectPath) = resolveS3URL(path: path)
        return try buildURLRequest(
            method: method,
            path: objectPath,
            queryParams: queryParams,
            body: nil,
            contentType: nil,
            baseURLOverride: baseURL,
            headers: [:],
            service: "s3",
            unsignedPayload: false
        )
    }

    private func buildURLRequest(
        method: String,
        path: String,
        queryParams: [String: String],
        body: Data?,
        contentType: String?,
        baseURLOverride: String? = nil,
        headers: [String: String] = [:],
        service: String? = nil,
        unsignedPayload: Bool = false,
        signingRegion: String? = nil
    ) throws -> URLRequest {
        let effectiveBase = baseURLOverride ?? baseURL

        // Percent-encode each path segment with the same RFC 3986 unreserved
        // set that SigV4 canonical URI uses. Without this, a key with a
        // space, trailing whitespace, or non-ASCII character (Cyrillic,
        // Greek, Arabic) either fails URLComponents parsing outright or ends
        // up encoded differently than the SigV4 canonical URI — producing
        // either invalidURL errors or SignatureDoesNotMatch from S3.
        var s3PathAllowed = CharacterSet.alphanumerics
        s3PathAllowed.insert(charactersIn: "-._~")
        let encodedPath = path.components(separatedBy: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: s3PathAllowed) ?? $0 }
            .joined(separator: "/")

        guard var components = URLComponents(string: effectiveBase + encodedPath) else {
            Log.error("Invalid URL: \(effectiveBase + encodedPath)", category: "HTTP")
            throw CloudClientError.invalidURL
        }

        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components.url else {
            Log.error("Invalid URL components: \(components)", category: "HTTP")
            throw CloudClientError.invalidURL
        }

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

        if let service, appState.needsSigning {
            SigV4Signer.sign(
                request: &urlRequest,
                body: body,
                region: signingRegion ?? appState.region,
                service: service,
                accessKeyId: appState.accessKeyId,
                secretAccessKey: appState.secretAccessKey,
                sessionToken: appState.sessionToken.isEmpty ? nil : appState.sessionToken,
                unsignedPayload: unsignedPayload
            )
        }

        return urlRequest
    }

    private func executeRequest(
        method: String,
        path: String,
        queryParams: [String: String],
        body: Data?,
        contentType: String?,
        baseURLOverride: String? = nil,
        headers: [String: String] = [:],
        skipReadOnlyCheck: Bool = false,
        service: String? = nil,
        unsignedPayload: Bool = false,
        signingRegion: String? = nil
    ) async throws -> HTTPResponse {
        guard skipReadOnlyCheck || ReadOnlyInterceptor.allowsRequest(method: method, isReadOnly: appState.isReadOnly) else {
            Log.warn("Blocked \(method) \(path) — read-only mode", category: "HTTP")
            throw CloudClientError.readOnlyBlocked(method: method)
        }

        let urlRequest = try buildURLRequest(
            method: method,
            path: path,
            queryParams: queryParams,
            body: body,
            contentType: contentType,
            baseURLOverride: baseURLOverride,
            headers: headers,
            service: service,
            unsignedPayload: unsignedPayload,
            signingRegion: signingRegion
        )

        Log.info("\(method) \(path)", category: "HTTP")

        let capturedSession = session
        let result: (Data, URLResponse)
        do {
            result = try await withRetry(
                operation: "\(method) \(path)"
            ) { @Sendable in
                let (d, r) = try await capturedSession.data(for: urlRequest)
                guard let http = r as? HTTPURLResponse else {
                    throw CloudClientError.invalidURL
                }
                if !(200..<300).contains(http.statusCode) {
                    var errHeaders: [String: String] = [:]
                    for (key, value) in http.allHeaderFields {
                        if let k = key as? String, let v = value as? String {
                            errHeaders[k.lowercased()] = v
                        }
                    }
                    throw CloudClientError.httpError(statusCode: http.statusCode, data: d, headers: errHeaders)
                }
                return (d, r)
            }
        } catch {
            // Detect expired credentials on non-retryable auth failures
            if let clientError = error as? CloudClientError,
               case .httpError(let code, let errData, _) = clientError,
               code == 401 || code == 403,
               let parsed = ServiceError.parse(from: errData) {
                if ["ExpiredToken", "ExpiredTokenException", "TokenRefreshRequired"].contains(parsed.code) {
                    appState.credentialExpired = true
                }
                if let service,
                   ["AccessDenied", "AccessDeniedException", "UnauthorizedOperation"].contains(parsed.code) {
                    appState.reportAccessDenied(service: service, message: parsed.message)
                }
            }
            throw error
        }

        let (data, response) = result

        guard let httpResponse = response as? HTTPURLResponse else {
            Log.error("\(method) \(path) — non-HTTP response", category: "HTTP")
            throw CloudClientError.invalidURL
        }

        Log.info("\(method) \(path) -> \(httpResponse.statusCode)", category: "HTTP")
        appState.notifyConnectionAlive()
        // Successful request proves permissions work — clear any lingering
        // permission-denied helper for this service.
        if let service, appState.permissionDeniedPrompts[service] != nil {
            appState.dismissPermissionPrompt(forService: service)
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k.lowercased()] = v
            }
        }

        return HTTPResponse(data: data, headers: responseHeaders)
    }
}

// MARK: - ListUserPolicies XML Parser

private final class ListUserPoliciesXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var policyNames: [String] = []
    private var currentText = ""

    init(data: Data) { self.data = data }

    func parse() -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return policyNames
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "member", !trimmed.isEmpty {
            policyNames.append(trimmed)
        }
    }
}

// MARK: - GetUserPolicy XML Parser

private final class GetUserPolicyXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var policyDocument: String?
    private var inDocument = false
    private var currentText = ""

    init(data: Data) { self.data = data }

    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return policyDocument
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "PolicyDocument" {
            inDocument = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inDocument { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "PolicyDocument" {
            policyDocument = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            inDocument = false
        }
    }
}

// MARK: - SimulatePrincipalPolicy XML Parser

private final class SimulatePolicyXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var allowedActions: Set<String> = []
    private var currentAction: String?
    private var currentDecision: String?
    private var currentElement: String?
    private var currentText = ""

    init(data: Data) { self.data = data }

    func parse() -> Set<String> {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return allowedActions
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "member" {
            currentAction = nil
            currentDecision = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "EvalActionName":
            currentAction = trimmed
        case "EvalDecision":
            currentDecision = trimmed
        case "member":
            if let action = currentAction, currentDecision == "allowed" {
                allowedActions.insert(action)
            }
            currentAction = nil
            currentDecision = nil
        default:
            break
        }
        currentElement = nil
    }
}
