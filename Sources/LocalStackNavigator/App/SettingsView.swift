import SwiftUI

struct SettingsView: View {
    @AppStorage("showFolderDetailsOnDelete") private var showFolderDetailsOnDelete = false
    @AppStorage(AppPreferences.restoreLastSessionKey) private var restoreLastSession = true
    @EnvironmentObject private var autoRefresh: AutoRefreshManager
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open where I left off", isOn: $restoreLastSession)
                Text("Restore the last viewed service, bucket, or queue when the app launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("S3 Browser") {
                Toggle("Show folder item count and size before deletion", isOn: $showFolderDetailsOnDelete)
                Text(
                    "When enabled, deleting a folder will first list all objects to show the total count and size. This requires additional API calls."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker("Auto-refresh interval", selection: $autoRefresh.interval) {
                    Text("Off").tag(0)
                    Text("1 second").tag(1)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }
            }

            Section("Quick Look Preview") {
                Stepper("Preview size limit: \(appState.previewSizeLimitMB) MB", value: $appState.previewSizeLimitMB, in: 1...50)
                Text(
                    "Files larger than this will prompt before downloading. Files over 300 MB cannot be previewed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
