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
        case .httpError(let statusCode, _):
            "HTTP error \(statusCode)"
        case .networkError(let underlying):
            "Network error: \(underlying.localizedDescription)"
        }
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

    private func executeRequest(
        method: String,
        path: String,
        queryParams: [String: String],
        body: Data?,
        contentType: String?
    ) async throws -> HTTPResponse {
        guard ReadOnlyInterceptor.allowsRequest(method: method, isReadOnly: appState.isReadOnly) else {
            Log.warn("Blocked \(method) \(path) — read-only mode", category: "HTTP")
            throw LocalStackClientError.readOnlyBlocked(method: method)
        }

        guard var components = URLComponents(string: baseURL + path) else {
            Log.error("Invalid URL: \(baseURL + path)", category: "HTTP")
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
