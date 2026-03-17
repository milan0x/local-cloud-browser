import Foundation

struct DetectedSettings: Sendable {
    var healthPath: String?
    var s3Domain: String?
    var apiGatewayDomain: String?
    var endpointType: EndpointType?

    var isEmpty: Bool { healthPath == nil && s3Domain == nil && apiGatewayDomain == nil && endpointType == nil }

    var detectedFieldNames: [String] {
        var names: [String] = []
        if endpointType != nil { names.append("endpointType") }
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

        // Step 1: Identify endpoint type
        let (detectedType, typeHealthPath) = await probeEndpointType(endpoint: endpoint)

        var result = DetectedSettings()
        result.endpointType = detectedType

        // Step 2: Set health path from type probe if needed
        if currentHealthPath.trimmingCharacters(in: .whitespaces).isEmpty {
            if let typeHealthPath {
                result.healthPath = typeHealthPath
            }
        }

        // Step 3: Conditionally probe remaining fields based on type
        switch detectedType {
        case .minio:
            // MinIO uses path-style S3, no API Gateway — skip those probes
            break

        case .localstack:
            // Probe s3Domain and apiGatewayDomain in parallel
            await withTaskGroup(of: (String, String?).self) { group in
                if currentS3Domain.trimmingCharacters(in: .whitespaces).isEmpty {
                    group.addTask { ("s3Domain", await probeS3Domain(endpoint: endpoint)) }
                }
                if currentApiGatewayDomain.trimmingCharacters(in: .whitespaces).isEmpty {
                    group.addTask { ("apiGatewayDomain", await probeApiGatewayDomain(endpoint: endpoint)) }
                }
                for await (field, value) in group {
                    guard let value else { continue }
                    switch field {
                    case "s3Domain": result.s3Domain = value
                    case "apiGatewayDomain": result.apiGatewayDomain = value
                    default: break
                    }
                }
            }

        case .generic:
            // Fall back to generic health probe if type probe didn't find a health path
            if result.healthPath == nil && currentHealthPath.trimmingCharacters(in: .whitespaces).isEmpty {
                result.healthPath = await probeGenericHealthPath(endpoint: endpoint)
            }
        }

        if !result.isEmpty {
            Log.info("Auto-detected: \(result.detectedFieldNames.joined(separator: ", "))", category: "Connection")
        }
        return result
    }

    /// Probes for LocalStack and MinIO health endpoints concurrently.
    /// Returns the detected type and the health path that succeeded.
    private static func probeEndpointType(endpoint: String) async -> (EndpointType, String?) {
        let base = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"

        return await withTaskGroup(of: (EndpointType, String?).self) { group in
            // Probe LocalStack: _localstack/health returns JSON with "version" key
            group.addTask {
                guard let url = URL(string: base + "_localstack/health") else { return (.generic, nil) }
                do {
                    let (data, response) = try await session.data(for: URLRequest(url: url))
                    if let http = response as? HTTPURLResponse,
                       (200..<300).contains(http.statusCode),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["version"] != nil {
                        return (.localstack, "_localstack/health")
                    }
                } catch {}
                return (.generic, nil)
            }

            // Probe MinIO: minio/health/live returns 200 with body containing "OK" (or empty body)
            group.addTask {
                guard let url = URL(string: base + "minio/health/live") else { return (.generic, nil) }
                do {
                    let (_, response) = try await session.data(for: URLRequest(url: url))
                    if let http = response as? HTTPURLResponse,
                       http.statusCode == 200 {
                        return (.minio, "minio/health/live")
                    }
                } catch {}
                return (.generic, nil)
            }

            // Return the first probe that identifies a specific type
            for await (type, path) in group {
                if type != .generic {
                    group.cancelAll()
                    return (type, path)
                }
            }
            return (.generic, nil)
        }
    }

    /// Probes generic health paths (used when neither LocalStack nor MinIO detected).
    private static func probeGenericHealthPath(endpoint: String) async -> String? {
        let candidates = ["health", "_health"]
        let base = endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
        for candidate in candidates {
            guard let url = URL(string: base + candidate) else { continue }
            do {
                let (_, response) = try await session.data(for: URLRequest(url: url))
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    Log.info("Auto-detected health path: \(candidate)", category: "Connection")
                    return candidate
                }
            } catch {}
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
