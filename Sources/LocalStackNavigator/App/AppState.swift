import SwiftUI

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
}

enum ConnectionError {
    case timeout
    case httpError(Int)
    case networkError(String)
}

struct ServiceHealth: Identifiable, Equatable {
    let id: String   // service name (e.g. "s3", "sqs")
    let status: String // raw value (e.g. "running", "error", "disabled")

    var isHealthy: Bool { status == "available" || status == "running" }
}

struct HealthInfo: Equatable {
    let version: String
    let edition: String
    let services: [ServiceHealth]

    var unhealthyServices: [ServiceHealth] { services.filter { !$0.isHealthy } }
    var hasIssues: Bool { !unhealthyServices.isEmpty }
}

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var healthInfo: HealthInfo?
    @Published var isReadOnly: Bool = false
    @Published var endpoint: String = "http://localhost:4566"
    @Published var selectedRoute: Route? = nil
    @Published var region: String = "us-east-1"
    @Published var activeConnectionName: String = "default connection"
    @Published var connectionVersion: Int = 0
    @Published var connectionError: ConnectionError?
    @Published var s3Clipboard: S3Clipboard?
    @Published var previewSizeLimitMB: Int = {
        let stored = UserDefaults.standard.integer(forKey: AppPreferences.previewSizeLimitMBKey)
        return stored > 0 ? stored : AppPreferences.defaultPreviewSizeLimitMB
    }() {
        didSet { UserDefaults.standard.set(previewSizeLimitMB, forKey: AppPreferences.previewSizeLimitMBKey) }
    }
    let autoRefresh = AutoRefreshManager()
    private var healthCheckTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    var previewSizeLimitBytes: Int64 { Int64(previewSizeLimitMB) * 1024 * 1024 }

    func applyProfile(_ profile: ConnectionProfile) {
        endpoint = profile.endpoint
        region = profile.region
        activeConnectionName = profile.name
        connectionVersion += 1
        connectionStatus = .disconnected
        consecutiveFailures = 0
        connectionError = nil
        startHealthCheck()
        Log.info("Applied profile \"\(profile.name)\" — endpoint: \(profile.endpoint), region: \(profile.region)", category: "App")
    }

    func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await performHealthCheck()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func performHealthCheck() async {
        guard let url = URL(string: endpoint + "/_localstack/health") else {
            connectionStatus = .disconnected
            healthInfo = nil
            return
        }

        // Race the request against a 5-second deadline
        let result: (ConnectionStatus, HealthInfo?, ConnectionError?) = await withTaskGroup(of: (ConnectionStatus, HealthInfo?, ConnectionError?).self) { group in
            group.addTask { @Sendable in
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 5
                config.timeoutIntervalForResource = 5
                let session = URLSession(configuration: config)
                defer { session.invalidateAndCancel() }
                do {
                    let (data, response) = try await session.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        return (.disconnected, nil, .httpError(httpResponse.statusCode))
                    }

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return (.connected, nil, nil)
                    }

                    let version = json["version"] as? String ?? "unknown"
                    let edition = json["edition"] as? String ?? "unknown"
                    let servicesDict = json["services"] as? [String: String] ?? [:]
                    let services = servicesDict
                        .map { ServiceHealth(id: $0.key, status: $0.value) }
                        .sorted { $0.id < $1.id }

                    return (.connected, HealthInfo(version: version, edition: edition, services: services), nil)
                } catch {
                    return (.disconnected, nil, .networkError(error.localizedDescription))
                }
            }

            group.addTask { @Sendable in
                try? await Task.sleep(for: .seconds(5))
                return (.disconnected, nil, .timeout)
            }

            let first = await group.next() ?? (.disconnected, nil, .timeout)
            group.cancelAll()
            return first
        }

        // Only update @Published properties when values actually change.
        // Unconditional assignment fires objectWillChange on every health check cycle,
        // which causes ContentView to re-render and dismiss popovers (e.g. region picker).
        if result.0 != connectionStatus {
            Log.info("Health check: \(result.0)", category: "App")
            connectionStatus = result.0
        }

        if result.0 == .connected {
            if consecutiveFailures != 0 { consecutiveFailures = 0 }
            if connectionError != nil { connectionError = nil }
            if healthInfo != result.1 { healthInfo = result.1 }
        } else {
            consecutiveFailures += 1
            let newError = consecutiveFailures >= 2 ? result.2 : nil
            if connectionError == nil && newError != nil || connectionError != nil && newError == nil {
                connectionError = newError
            }
            if healthInfo != nil { healthInfo = nil }
        }
    }

    var isLocalEndpoint: Bool {
        guard let url = URL(string: endpoint),
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasSuffix(".local")
    }
}
