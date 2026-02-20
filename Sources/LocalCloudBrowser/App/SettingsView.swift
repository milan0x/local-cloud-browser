import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case s3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: "General"
        case .s3: "S3"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .s3: "externaldrive"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @AppStorage("showFolderDetailsOnDelete") private var showFolderDetailsOnDelete = false
    @AppStorage(AppPreferences.restoreLastSessionKey) private var restoreLastSession = true
    @AppStorage(AppPreferences.doubleClickHidesJsonHelperKey) private var doubleClickHidesJsonHelper = false
    @AppStorage(AppPreferences.disableJsonHelperPlaceholdersKey) private var disablePlaceholders = false
    @EnvironmentObject private var autoRefresh: AutoRefreshManager
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.displayName, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 150)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    generalSettings
                case .s3:
                    s3Settings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 600)
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Session") {
                Toggle("Open where I left off", isOn: $restoreLastSession)
                Text("Restore the last viewed service, bucket, or queue when the app launches. Switching between services always remembers your selection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                Picker("Health check interval", selection: $appState.healthCheckInterval) {
                    Text("1 second").tag(1.0)
                    Text("1.5 seconds").tag(1.5)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("4 seconds").tag(4.0)
                    Text("5 seconds").tag(5.0)
                }
                Text("How often to check the connection status. Lower values detect connection changes faster.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Auto-Refresh") {
                Picker("Refresh interval", selection: $autoRefresh.interval) {
                    Text("Off").tag(0)
                    Text("1 second").tag(1)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }
                Text("Automatically refreshes lists across all modules at the configured interval. Also editable via the refresh menu in each module's toolbar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("JSON Helper") {
                Toggle("Disable placeholders", isOn: $disablePlaceholders)
                Text("Hides placeholder text in JSON input editors.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Double-click body to close JSON Helper", isOn: $doubleClickHidesJsonHelper)
                Text("When enabled, double-clicking the read-only editor when the JSON Helper is open will close the helper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - S3

    private var s3Settings: some View {
        Form {
            Section("Quick Look") {
                Stepper("Preview size limit: \(appState.previewSizeLimitMB) MB", value: $appState.previewSizeLimitMB, in: 1...50)
                Text("Files larger than this will prompt before downloading. Files over 300 MB cannot be previewed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Folders") {
                Toggle("Show item count and size before deletion", isOn: $showFolderDetailsOnDelete)
                Text("When enabled, deleting a folder will first list all objects to show the total count and size. This requires additional API calls.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
