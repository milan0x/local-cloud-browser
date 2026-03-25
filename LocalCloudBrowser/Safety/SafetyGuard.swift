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

        if isPrivateIP(host) {
            Log.info("Endpoint \(endpoint) classified as local (private IP)", category: "Safety")
            return .local
        }

        Log.warn("Endpoint \(endpoint) is non-local (host: \(host))", category: "Safety")
        return .cautionNonLocal
    }

    /// Checks whether a hostname string is an RFC 1918 private IP or link-local address.
    static func isPrivateIP(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }

        switch parts[0] {
        case 10:
            // 10.0.0.0/8
            return true
        case 172:
            // 172.16.0.0/12 (172.16.x – 172.31.x)
            return parts[1] >= 16 && parts[1] <= 31
        case 192:
            // 192.168.0.0/16
            return parts[1] == 168
        case 169:
            // 169.254.0.0/16 (link-local)
            return parts[1] == 254
        default:
            return false
        }
    }
}
