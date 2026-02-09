import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isReadOnly: Bool = false
    @Published var endpoint: String = "http://localhost:4566"
    @Published var selectedRoute: Route? = nil
    @Published var region: String = "us-east-1"
    @Published var activeConnectionName: String = "Default"
    @Published var connectionVersion: Int = 0

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
