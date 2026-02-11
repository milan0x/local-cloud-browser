import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isConnected: Bool = false
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
        isConnected = false
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
            isConnected = false
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            isConnected = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isConnected = false
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
