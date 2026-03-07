import Foundation

struct DetectedSettings: Sendable {
    var healthPath: String?
    var s3Domain: String?
    var apiGatewayDomain: String?

    var isEmpty: Bool { healthPath == nil && s3Domain == nil && apiGatewayDomain == nil }

    var detectedFieldNames: [String] {
        var names: [String] = []
        if healthPath != nil { names.append("healthPath") }
        if s3Domain != nil { names.append("s3Domain") }
        if apiGatewayDomain != nil { names.append("apiGatewayDomain") }
        return names
    }
}

enum EndpointDetector {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        return URLSession(configuration: config)
    }()

    /// Probes the endpoint for known service patterns.
    /// Only probes fields where the current value is empty.
    static func detect(
        endpoint: String,
        currentHealthPath: String = "",
        currentS3Domain: String = "",
        currentApiGatewayDomain: String = ""
    ) async -> DetectedSettings {
        guard SafetyGuard.evaluate(endpoint: endpoint) == .local else {
            return DetectedSettings()
        }

        Log.info("Starting auto-detection for \(endpoint)", category: "Connection")

        return await withTaskGroup(of: (String, String?).self) { group in
            if currentHealthPath.trimmingCharacters(in: .whitespaces).isEmpty {
                group.addTask { ("healthPath", await probeHealthPath(endpoint: endpoint)) }
            }
            if currentS3Domain.trimmingCharacters(in: .whitespaces).isEmpty {
                group.addTask { ("s3Domain", await probeS3Domain(endpoint: endpoint)) }
            }
            if currentApiGatewayDomain.trimmingCharacters(in: .whitespaces).isEmpty {
                group.addTask { ("apiGatewayDomain", await probeApiGatewayDomain(endpoint: endpoint)) }
            }

            var result = DetectedSettings()
            for await (field, value) in group {
                guard let value else { continue }
                switch field {
                case "healthPath": result.healthPath = value
                case "s3Domain": result.s3Domain = value
                case "apiGatewayDomain": result.apiGatewayDomain = value
                default: break
                }
            }

            if !result.isEmpty {
                Log.info("Auto-detected: \(result.detectedFieldNames.joined(separator: ", "))", category: "Connection")
            }
            return result
        }
    }

    private static func probeHealthPath(endpoint: String) async -> String? {
        let candidates = ["_localstack/health", "health", "_health"]
        let base = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        for candidate in candidates {
            guard let url = URL(string: base + candidate) else { continue }
            do {
                let (_, response) = try await session.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    Log.info("Auto-detected health path: \(candidate)", category: "Connection")
                    return candidate
                }
            } catch {
                // Probe failed, try next candidate
            }
        }
        return nil
    }

    private static func probeS3Domain(endpoint: String) async -> String? {
        let candidates = ["s3.localhost.localstack.cloud"]
        guard let endpointURL = URL(string: endpoint),
              let port = endpointURL.port else { return nil }
        for candidate in candidates {
            guard let url = URL(string: "http://\(candidate):\(port)/") else { continue }
            do {
                let (data, response) = try await session.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode),
                   let body = String(data: data, encoding: .utf8),
                   body.contains("ListAllMyBucketsResult") {
                    Log.info("Auto-detected S3 domain: \(candidate)", category: "Connection")
                    return candidate
                }
            } catch {
                // Probe failed, try next candidate
            }
        }
        return nil
    }

    private static func probeApiGatewayDomain(endpoint: String) async -> String? {
        let candidates = ["execute-api.localhost.localstack.cloud"]
        guard let endpointURL = URL(string: endpoint),
              let port = endpointURL.port else { return nil }
        for candidate in candidates {
            guard let url = URL(string: "http://\(candidate):\(port)/") else { continue }
            do {
                let (_, response) = try await session.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    Log.info("Auto-detected API Gateway domain: \(candidate)", category: "Connection")
                    return candidate
                }
            } catch {
                // Probe failed, try next candidate
            }
        }
        return nil
    }
}
