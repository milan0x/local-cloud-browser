import Foundation

struct DiscoveredService: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let endpoint: String
    let port: Int
    let endpointType: EndpointType
    let accessKeyId: String
    let secretAccessKey: String
    let s3Domain: String
    let healthPath: String
    let version: String?
}

enum LocalServiceScanner {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }()

    private struct Probe: Sendable {
        let port: Int
        let name: String
        let endpointType: EndpointType
        let healthPath: String
        let accessKeyId: String
        let secretAccessKey: String
        let s3Domain: String
    }

    private static let probes: [Probe] = [
        Probe(
            port: 4566,
            name: "LocalStack",
            endpointType: .localstack,
            healthPath: "_localstack/health",
            accessKeyId: "test",
            secretAccessKey: "test",
            s3Domain: "s3.localhost.localstack.cloud"
        ),
        Probe(
            port: 9000,
            name: "MinIO",
            endpointType: .minio,
            healthPath: "minio/health/live",
            accessKeyId: "minioadmin",
            secretAccessKey: "minioadmin",
            s3Domain: ""
        ),
        Probe(
            port: 5000,
            name: "LocalStack",
            endpointType: .localstack,
            healthPath: "_localstack/health",
            accessKeyId: "test",
            secretAccessKey: "test",
            s3Domain: "s3.localhost.localstack.cloud"
        ),
    ]

    static func scan() async -> [DiscoveredService] {
        await withTaskGroup(of: DiscoveredService?.self) { group in
            for probe in probes {
                group.addTask { await check(probe) }
            }
            var results: [DiscoveredService] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.port < $1.port }
        }
    }

    private static func check(_ probe: Probe) async -> DiscoveredService? {
        let base = "http://localhost:\(probe.port)"
        guard let url = URL(string: "\(base)/\(probe.healthPath)") else { return nil }
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else { return nil }

            switch probe.endpointType {
            case .localstack:
                guard (200..<300).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["version"] != nil else { return nil }
                let version = json["version"] as? String
                return DiscoveredService(
                    name: probe.name,
                    endpoint: base,
                    port: probe.port,
                    endpointType: probe.endpointType,
                    accessKeyId: probe.accessKeyId,
                    secretAccessKey: probe.secretAccessKey,
                    s3Domain: probe.s3Domain,
                    healthPath: probe.healthPath,
                    version: version
                )
            case .minio:
                guard http.statusCode == 200 else { return nil }
                return DiscoveredService(
                    name: probe.name,
                    endpoint: base,
                    port: probe.port,
                    endpointType: probe.endpointType,
                    accessKeyId: probe.accessKeyId,
                    secretAccessKey: probe.secretAccessKey,
                    s3Domain: probe.s3Domain,
                    healthPath: probe.healthPath,
                    version: nil
                )
            case .generic:
                return nil
            }
        } catch {
            return nil
        }
    }
}
