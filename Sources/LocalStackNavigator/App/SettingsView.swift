import SwiftUI

struct SettingsView: View {
    @AppStorage("showFolderDetailsOnDelete") private var showFolderDetailsOnDelete = false

    var body: some View {
        Form {
            Section("S3 Browser") {
                Toggle("Show folder item count and size before deletion", isOn: $showFolderDetailsOnDelete)
                Text(
                    "When enabled, deleting a folder will first list all objects to show the total count and size. This requires additional API calls."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }
}
