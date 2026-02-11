import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isReadOnly: Bool = false
    @Published var endpoint: String = "http://localhost:4566"
    @Published var selectedRoute: Route? = nil
    @Published var region: String = {
        let stored = UserDefaults.standard.string(forKey: AppPreferences.regionKey)
        return (stored != nil && !stored!.isEmpty) ? stored! : "us-east-1"
    }() {
        didSet { UserDefaults.standard.set(region, forKey: AppPreferences.regionKey) }
    }
    @Published var activeConnectionName: String = "Default Connection"
    @Published var connectionVersion: Int = 0
    @Published var s3Clipboard: S3Clipboard?
    @Published var previewSizeLimitMB: Int = {
        let stored = UserDefaults.standard.integer(forKey: AppPreferences.previewSizeLimitMBKey)
        return stored > 0 ? stored : AppPreferences.defaultPreviewSizeLimitMB
    }() {
        didSet { UserDefaults.standard.set(previewSizeLimitMB, forKey: AppPreferences.previewSizeLimitMBKey) }
    }
    let autoRefresh = AutoRefreshManager()

    var previewSizeLimitBytes: Int64 { Int64(previewSizeLimitMB) * 1024 * 1024 }

    func applyProfile(_ profile: ConnectionProfile) {
        endpoint = profile.endpoint
        region = profile.region
        activeConnectionName = profile.name
        connectionVersion += 1
        Log.info("Applied profile \"\(profile.name)\" — endpoint: \(profile.endpoint), region: \(profile.region)", category: "App")
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
