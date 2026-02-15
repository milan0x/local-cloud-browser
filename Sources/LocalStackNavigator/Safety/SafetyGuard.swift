import Foundation

enum EndpointSafety: Equatable {
    case local
    case cautionNonLocal
}

struct SafetyGuard {
    static func evaluate(endpoint: String) -> EndpointSafety {
        guard let url = URL(string: endpoint),
              let host = url.host?.lowercased() else {
            Log.warn("Cannot parse endpoint \"\(endpoint)\" — treating as non-local", category: "Safety")
            return .cautionNonLocal
        }

        if host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".local") {
            Log.info("Endpoint \(endpoint) classified as local", category: "Safety")
            return .local
        }

        Log.warn("Endpoint \(endpoint) is non-local (host: \(host))", category: "Safety")
        return .cautionNonLocal
    }
}
