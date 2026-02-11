import SwiftUI

enum ConnectionStatus: Equatable {
    case connected
    case unhealthy
    case disconnected
}

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isReadOnly: Bool = false
    @Published var endpoint: String = "http://localhost:4566"
    @Published var selectedRoute: Route? = nil
    @Published var region: String = "us-east-1"
    @Published var activeConnectionName: String = "default connection"
    @Published var connectionVersion: Int = 0
    @Published var s3Clipboard: S3Clipboard?
    @Published var previewSizeLimitMB: Int = {
        let stored = UserDefaults.standard.integer(forKey: AppPreferences.previewSizeLimitMBKey)
        return stored > 0 ? stored : AppPreferences.defaultPreviewSizeLimitMB
    }() {
        didSet { UserDefaults.standard.set(previewSizeLimitMB, forKey: AppPreferences.previewSizeLimitMBKey) }
    }
    let autoRefresh = AutoRefreshManager()
    private var healthCheckTask: Task<Void, Never>?

    var previewSizeLimitBytes: Int64 { Int64(previewSizeLimitMB) * 1024 * 1024 }

    func applyProfile(_ profile: ConnectionProfile) {
        endpoint = profile.endpoint
        region = profile.region
        activeConnectionName = profile.name
        connectionVersion += 1
        connectionStatus = .disconnected
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
            return
        }

        // Race the request against a 2-second deadline
        let result: ConnectionStatus = await withTaskGroup(of: ConnectionStatus.self) { group in
            group.addTask { @Sendable in
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 2
                config.timeoutIntervalForResource = 2
                let session = URLSession(configuration: config)
                defer { session.invalidateAndCancel() }
                do {
                    let start = ContinuousClock.now
                    let (_, response) = try await session.data(from: url)
                    let elapsed = ContinuousClock.now - start
                    let isOk = (response as? HTTPURLResponse)?.statusCode == 200
                    if isOk && elapsed < .seconds(1) {
                        return .connected
                    } else if isOk {
                        return .unhealthy
                    } else {
                        return .disconnected
                    }
                } catch {
                    return .disconnected
                }
            }

            group.addTask { @Sendable in
                try? await Task.sleep(for: .seconds(2))
                return .disconnected
            }

            let first = await group.next() ?? .disconnected
            group.cancelAll()
            return first
        }

        if result != connectionStatus {
            Log.info("Health check: \(result)", category: "App")
        }
        connectionStatus = result
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
