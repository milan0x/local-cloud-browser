import SwiftUI
import AppKit

struct ConfigDeliveryChannelListView: View {
    @ObservedObject var service: ConfigService
    @ObservedObject var toolbarState: ConfigToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedChannelIDs: Set<DeliveryChannel.ID>
    @Binding var activeChannel: DeliveryChannel?
    var restoreChannelName: String?

    @State private var showCreateSheet = false
    @State private var channelsToDelete: [DeliveryChannel] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<DeliveryChannel>()
    private var channels: [DeliveryChannel] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            channelListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            ConfigCreateDeliveryChannelView(service: service)
                .onDisappear { loadChannels(force: true) }
        }
        .alert(
            channelsToDelete.count == 1
                ? "Delete Delivery Channel"
                : "Delete \(channelsToDelete.count) Delivery Channels",
            isPresented: Binding(
                get: { !channelsToDelete.isEmpty },
                set: { if !$0 { channelsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteChannels(channelsToDelete)
            }
            Button("Cancel", role: .cancel) {
                channelsToDelete = []
            }
        } message: {
            if channelsToDelete.count == 1, let channel = channelsToDelete.first {
                Text("Are you sure you want to delete delivery channel \"\(channel.name)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(channelsToDelete.count) delivery channels?\n\nThis action cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadChannels() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && channelsToDelete.isEmpty && !loader.isLoading }) {
            loadChannels(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedChannelIDs = []
            activeChannel = nil
            loader.items = []
            loadChannels(force: true)
        }
        .syncSelection(selectedChannelIDs, items: channels, activeItem: $activeChannel)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createChannel:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteChannel:
                toolbarState.pendingAction = nil
                if let active = activeChannel {
                    channelsToDelete = [active]
                }
            case .createRecorder, .deleteRecorder:
                break
            }
        }
    }

    private var filteredChannels: [DeliveryChannel] {
        guard !searchText.isEmpty else { return channels }
        let query = searchText.lowercased()
        return channels.filter {
            $0.name.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var channelListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: channels.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading delivery channels...", onRetry: { loadChannels(force: true) }) {
            if channels.isEmpty {
                EmptyStateView(icon: "tray.and.arrow.down", message: "No delivery channels")
                .contextMenu {
                    Button("Create Delivery Channel") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                VStack(spacing: 0) {
                if channels.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter channels")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredChannels, selection: $selectedChannelIDs) { channel in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if !channel.s3BucketName.isEmpty {
                            Text(channel.s3BucketName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selectedChannelIDs.contains(channel.id) ? Color.white : Color.primary)
                    .tag(channel.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(channel.name) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Channel") {
                                copyToClipboard(channel.describeChannelCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Channels") {
                                copyToClipboard(DeliveryChannel.listChannelsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Delivery Channel") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Delete", role: .destructive) {
                            channelsToDelete = [channel]
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Delivery Channel") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                Divider()
                HStack {
                    Text("\(channels.count) channel\(channels.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            }
        }
    }

    // MARK: - Data

    private func loadChannels(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.describeDeliveryChannels() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreChannelName,
               let channel = items.first(where: { $0.name == savedName }) {
                selectedChannelIDs = [channel.id]
                activeChannel = channel
            }
            loader.hasRestoredSession = true
        }
    }

    private func deleteChannels(_ targets: [DeliveryChannel]) {
        Task {
            var deletedIDs: Set<DeliveryChannel.ID> = []
            for channel in targets {
                do {
                    try await service.deleteDeliveryChannel(name: channel.name)
                    deletedIDs.insert(channel.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedChannelIDs.subtract(deletedIDs)
                if let active = activeChannel, deletedIDs.contains(active.id) {
                    activeChannel = nil
                }
                loadChannels(force: true)
            }
        }
    }
}
