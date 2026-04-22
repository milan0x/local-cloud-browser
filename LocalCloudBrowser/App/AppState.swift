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

struct HealthEntry: Identifiable, Equatable {
    let id: String   // key name
    let value: String // display value
}

struct HealthInfo: Equatable {
    let entries: [HealthEntry]
}

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var healthInfo: HealthInfo?
    @Published var isReadOnly: Bool = UserDefaults.standard.bool(forKey: AppPreferences.isReadOnlyKey) {
        didSet { UserDefaults.standard.set(isReadOnly, forKey: AppPreferences.isReadOnlyKey) }
    }
    @Published var endpoint: String = "http://localhost:4566"
    @Published var healthPath: String = ConnectionProfile.defaultHealthPath
    @Published var s3Domain: String = ConnectionProfile.defaultS3Domain
    @Published var apiGatewayDomain: String = ConnectionProfile.defaultApiGatewayDomain
    @Published var endpointType: EndpointType = .generic
    @Published var selectedRoute: Route? = nil
    @Published var region: String = "us-east-1"
    @Published var accessKeyId: String = KeychainHelper.defaultAccessKeyId
    @Published var secretAccessKey: String = KeychainHelper.defaultSecretAccessKey
    @Published var sessionToken: String = ""
    @Published var activeConnectionName: String = "My Connection"
    @Published var connectionVersion: Int = 0
    @Published var connectionError: ConnectionError?
    @Published var credentialExpired = false
    @Published var s3Clipboard: S3Clipboard?
    @Published var editActiveProfileRequest: EditProfileRequest?

    struct EditProfileRequest {
        var showAdvanced: Bool = false
    }
    @Published var previewSizeLimitMB: Int = {
        let stored = UserDefaults.standard.integer(forKey: AppPreferences.previewSizeLimitMBKey)
        return stored > 0 ? stored : AppPreferences.defaultPreviewSizeLimitMB
    }() {
        didSet { UserDefaults.standard.set(previewSizeLimitMB, forKey: AppPreferences.previewSizeLimitMBKey) }
    }
    @Published var healthCheckInterval: Double = {
        let stored = UserDefaults.standard.double(forKey: AppPreferences.healthCheckIntervalKey)
        return stored > 0 ? stored : AppPreferences.defaultHealthCheckInterval
    }() {
        didSet {
            UserDefaults.standard.set(healthCheckInterval, forKey: AppPreferences.healthCheckIntervalKey)
            startHealthCheck()
        }
    }
    // Pane focus triggers (sidebar ↔ module list)
    @Published var sidebarFocusTrigger = 0
    @Published var moduleListFocusTrigger = 0

    let autoRefresh = AutoRefreshManager()
    /// Called when auto-detection fills in advanced settings on connect.
    /// The closure receives the active profile ID and the detected settings so they can be persisted.
    var onSettingsDetected: ((UUID, DetectedSettings) -> Void)?
    private let healthSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()
    private var healthCheckTask: Task<Void, Never>?
    private var detectionTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var activeProfileId: UUID?
    private var hasDetectedForCurrentProfile = false

    var previewSizeLimitBytes: Int64 { Int64(previewSizeLimitMB) * 1024 * 1024 }

    var needsSigning: Bool {
        endpointType != .localstack
            && !accessKeyId.isEmpty
            && !secretAccessKey.isEmpty
            && !(accessKeyId == KeychainHelper.defaultAccessKeyId
                 && secretAccessKey == KeychainHelper.defaultSecretAccessKey)
    }

    func applyProfile(_ profile: ConnectionProfile) {
        endpoint = profile.endpoint
        region = profile.region
        healthPath = profile.healthPath
        s3Domain = profile.s3Domain
        apiGatewayDomain = profile.apiGatewayDomain
        endpointType = profile.endpointType
        accessKeyId = profile.accessKeyId
        secretAccessKey = profile.secretAccessKey
        sessionToken = profile.sessionToken
        if profile.endpointType == .minio { region = "us-east-1" }
        activeConnectionName = profile.name
        activeProfileId = profile.id
        hasDetectedForCurrentProfile = false
        detectionTask?.cancel()
        connectionVersion += 1
        connectionStatus = .disconnected
        consecutiveFailures = 0
        connectionError = nil
        credentialExpired = false
        startHealthCheck()
        runAutoDetection()
        Log.info("Applied profile \"\(profile.name)\" — endpoint: \(profile.endpoint), region: \(profile.region)", category: "App")
    }

    func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await performHealthCheck()
                try? await Task.sleep(for: .seconds(healthCheckInterval))
            }
        }
    }

    private func performHealthCheck() async {
        let healthURL: String
        if healthPath.trimmingCharacters(in: .whitespaces).isEmpty {
            healthURL = endpoint
        } else {
            if var components = URLComponents(string: endpoint) {
                components.path = components.path.hasSuffix("/")
                    ? components.path + healthPath
                    : components.path + "/" + healthPath
                healthURL = components.string ?? endpoint + "/" + healthPath
            } else {
                healthURL = endpoint + "/" + healthPath
            }
        }

        guard let url = URL(string: healthURL) else {
            connectionStatus = .disconnected
            healthInfo = nil
            return
        }

        // Race the request against a 5-second deadline
        let session = healthSession
        let result: (ConnectionStatus, HealthInfo?, ConnectionError?) = await withTaskGroup(of: (ConnectionStatus, HealthInfo?, ConnectionError?).self) { group in
            group.addTask { @Sendable in
                do {
                    let (data, response) = try await session.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                        return (.disconnected, nil, .httpError(httpResponse.statusCode))
                    }

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return (.connected, nil, nil)
                    }

                    let entries = json
                        .sorted { $0.key < $1.key }
                        .compactMap { key, value -> HealthEntry? in
                            if let stringValue = value as? String {
                                return HealthEntry(id: key, value: stringValue)
                            } else if let number = value as? NSNumber {
                                return HealthEntry(id: key, value: "\(number)")
                            } else if let dict = value as? [String: Any] {
                                return HealthEntry(id: key, value: "\(dict.count) items")
                            } else if let array = value as? [Any] {
                                return HealthEntry(id: key, value: "\(array.count) items")
                            } else if let bool = value as? Bool {
                                return HealthEntry(id: key, value: bool ? "true" : "false")
                            }
                            return nil
                        }

                    return (.connected, HealthInfo(entries: entries), nil)
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
        let wasDisconnected = connectionStatus == .disconnected
        if result.0 != connectionStatus {
            Log.info("Health check: \(result.0)", category: "App")
            connectionStatus = result.0
        }
        if wasDisconnected && result.0 == .connected {
            autoRefresh.triggerNow()
            if !hasDetectedForCurrentProfile {
                hasDetectedForCurrentProfile = true
                runAutoDetection()
            }
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

    /// Called by CloudClient when any API request succeeds.
    /// Immediately flips the health indicator to connected without waiting
    /// for the next health check cycle.
    func notifyConnectionAlive() {
        if connectionStatus != .connected {
            connectionStatus = .connected
        }
        if consecutiveFailures != 0 { consecutiveFailures = 0 }
        if connectionError != nil { connectionError = nil }
    }

    private func runAutoDetection() {
        let ep = endpoint
        let hp = healthPath
        let s3 = s3Domain
        let apigw = apiGatewayDomain
        let profileId = activeProfileId

        detectionTask = Task {
            let result = await EndpointDetector.detect(
                endpoint: ep,
                currentHealthPath: hp,
                currentS3Domain: s3,
                currentApiGatewayDomain: apigw
            )
            guard !Task.isCancelled, !result.isEmpty else {
                Log.info("Auto-detection returned empty for \(ep)", category: "Connection")
                return
            }

            if let value = result.endpointType {
                endpointType = value
                Log.info("Detected endpoint type: \(value)", category: "Connection")
                if value == .minio { region = "us-east-1" }
            }
            if let value = result.healthPath { healthPath = value }
            if let value = result.s3Domain { s3Domain = value }
            if let value = result.apiGatewayDomain { apiGatewayDomain = value }

            if let profileId {
                onSettingsDetected?(profileId, result)
            }

            // If we discovered a health path, restart health check immediately
            // so it uses the new path (fixes MinIO/non-LocalStack endpoints
            // where the root endpoint requires auth).
            if result.healthPath != nil {
                startHealthCheck()
            }
        }
    }

    var isLocalEndpoint: Bool {
        SafetyGuard.evaluate(endpoint: endpoint) == .local
    }
}
