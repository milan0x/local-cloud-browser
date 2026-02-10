import SwiftUI

struct SettingsView: View {
    @AppStorage("showFolderDetailsOnDelete") private var showFolderDetailsOnDelete = false
    @EnvironmentObject private var autoRefresh: AutoRefreshManager

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
