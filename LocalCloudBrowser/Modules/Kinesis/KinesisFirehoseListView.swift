import SwiftUI
import AppKit

struct KinesisFirehoseListView: View {
    @ObservedObject var service: KinesisFirehoseService
    @ObservedObject var toolbarState: KinesisToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedStreamIDs: Set<FirehoseDeliveryStreamSummary.ID>
    @Binding var activeStream: FirehoseDeliveryStreamSummary?
    var restoreDeliveryStreamName: String?

    @State private var showCreateSheet = false
    @State private var streamsToDelete: [FirehoseDeliveryStreamSummary] = []
    @State private var showPutRecordSheet = false
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = PaginatedListLoader<FirehoseDeliveryStreamSummary>()
    private var streams: [FirehoseDeliveryStreamSummary] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            streamListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            KinesisFirehoseCreateView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadStreams(force: true) }
        }
        .sheet(isPresented: $showPutRecordSheet) {
            if let stream = activeStream {
                KinesisFirehosePutRecordView(service: service, deliveryStreamName: stream.deliveryStreamName)
            }
        }
        .deleteConfirmation(items: $streamsToDelete, noun: "Delivery Stream") { items in
            if items.count == 1, let stream = items.first {
                Text("Are you sure you want to delete delivery stream \"\(stream.deliveryStreamName)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(items.count) delivery streams?\n\nThis action cannot be undone.")
            }
        } onDelete: { deleteStreams($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadStreams() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && streamsToDelete.isEmpty && !showPutRecordSheet && !loader.isLoading }) {
            loadStreams(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedStreamIDs = []
            activeStream = nil
            loader.items = []
            loadStreams(force: true)
        }
        .syncSelection(selectedStreamIDs, items: streams, activeItem: $activeStream)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createDeliveryStream:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .putFirehoseRecord:
                toolbarState.pendingAction = nil
                if activeStream != nil {
                    showPutRecordSheet = true
                }
            case .deleteDeliveryStream:
                toolbarState.pendingAction = nil
                if let active = activeStream {
                    streamsToDelete = [active]
                }
            case .createStream, .putRecord, .deleteStream:
                break
            }
        }
    }

    private var deleteDisabled: Bool {
        appState.isReadOnly || selectedStreamIDs.isEmpty
    }

    private var filteredStreams: [FirehoseDeliveryStreamSummary] {
        guard !searchText.isEmpty else { return streams }
        let query = searchText.lowercased()
        return streams.filter {
            $0.deliveryStreamName.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var streamListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: streams.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading delivery streams...", emptyIcon: "flame", emptyMessage: "No delivery streams", onRetry: { loadStreams(force: true) }) {
            VStack(spacing: 0) {
                if streams.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter delivery streams")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedStreamIDs) {
                    ForEach(filteredStreams) { stream in
                    HStack {
                        Text(stream.deliveryStreamName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        typeBadge(stream.deliveryStreamType)
                        statusBadge(stream.deliveryStreamStatus)
                    }
                    .selectionForeground()
                    .tag(stream.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(stream.deliveryStreamName) }
                        Button("Copy ARN") { copyToClipboard(stream.deliveryStreamARN) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Delivery Stream") {
                                copyToClipboard(stream.describeStreamCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Delivery Streams") {
                                copyToClipboard(FirehoseDeliveryStreamSummary.listStreamsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Delete Delivery Stream") {
                                copyToClipboard(stream.deleteStreamCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Delivery Stream") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedStreamIDs.count > 1 && selectedStreamIDs.contains(stream.id) {
                            let selected = streams.filter { selectedStreamIDs.contains($0.id) }
                            Button("Delete (\(selected.count) Streams)", role: .destructive) {
                                streamsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                streamsToDelete = [stream]
                            }
                            .disabled(appState.isReadOnly)
                        }
                    }
                    }
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Delivery Stream") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                if loader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            loader.loadMore()
                        } label: {
                            if loader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(loader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredStreams.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.deliveryStreamName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if loader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if loader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                ListStatusBar(totalCount: streams.count, selectedCount: selectedStreamIDs.count, noun: "delivery stream", hasMorePages: loader.hasMorePages)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: statusColor(status))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ACTIVE": .green
        case "CREATING": .orange
        case "DELETING", "DELETING_FAILED", "CREATING_FAILED": .red
        default: .gray
        }
    }

    private func typeBadge(_ type: String) -> some View {
        StatusBadge(text: type, color: typeColor(type))
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "KinesisStreamAsSource": .purple
        default: .gray
        }
    }

    // MARK: - Data

    private func loadStreams(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listDeliveryStreamsPage(token: token) },
            sort: { $0.deliveryStreamName.localizedStandardCompare($1.deliveryStreamName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreDeliveryStreamName,
               let stream = items.first(where: { $0.deliveryStreamName == savedName }) {
                selectedStreamIDs = [stream.id]
                activeStream = stream
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let stream = items.first(where: { $0.deliveryStreamName == name }) {
                selectedStreamIDs = [stream.id]
                activeStream = stream
                pendingSelectName = nil
            }
        }
    }

    private func deleteStreams(_ targets: [FirehoseDeliveryStreamSummary]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteDeliveryStream(name: $0.deliveryStreamName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .kinesis, by: deleted.count)
                selectedStreamIDs.subtract(deleted)
                if let active = activeStream, deleted.contains(active.id) { activeStream = nil }
                loadStreams(force: true)
            }
        }
    }
}
