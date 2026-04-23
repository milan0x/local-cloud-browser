import SwiftUI

/// Popover-style region picker shown from the sidebar bottom bar.
/// Clicking a region updates both the app state and the underlying connection
/// profile, plus rewrites the S3 endpoint URL to match.
struct RegionPickerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @EnvironmentObject private var transferManager: TransferManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var isLocalEndpoint: Bool {
        appState.endpointType == .minio || appState.endpointType == .localstack
    }

    private func matches(_ region: AWSRegion) -> Bool {
        if searchText.isEmpty { return true }
        let query = searchText.lowercased()
        return region.code.lowercased().contains(query)
            || region.displayName.lowercased().contains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            Divider()
            regionList
        }
        .frame(width: 300, height: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Region")
                .font(.headline)
            Spacer()
            if isLocalEndpoint {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("You are connected to a local service. In some services, the region is global or may not affect behavior.")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        TextField("Search regions", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private var regionList: some View {
        let filtered = AWSRegion.allRegions.filter { matches($0) }
        return List {
            ForEach(filtered, id: \.code) { region in
                regionRow(region)
            }
        }
        .listStyle(.plain)
    }

    private func regionRow(_ region: AWSRegion) -> some View {
        Button {
            selectRegion(region.code)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.code)
                        .font(.body)
                    Text(region.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if region.code == appState.region {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectRegion(_ code: String) {
        guard code != appState.region else {
            dismiss()
            return
        }
        appState.region = code
        // For AWS endpoints, also update the endpoint URL to match the region.
        appState.endpoint = AWSRegion.updateEndpointRegion(appState.endpoint, to: code)
        if var profile = profileStore.activeProfile {
            profile.region = code
            profile.endpoint = AWSRegion.updateEndpointRegion(profile.endpoint, to: code)
            profileStore.update(profile)
        }
        dismiss()
    }
}
