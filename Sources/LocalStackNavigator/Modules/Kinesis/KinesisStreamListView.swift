import SwiftUI
import AppKit

struct KinesisStreamListView: View {
    @ObservedObject var service: KinesisService
    @ObservedObject var toolbarState: KinesisToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedStreamIDs: Set<KinesisStreamSummary.ID>
    @Binding var activeStream: KinesisStreamSummary?
    var restoreStreamName: String?

    @State private var showCreateSheet = false
    @State private var streamsToDelete: [KinesisStreamSummary] = []
    @State private var showPutRecordSheet = false
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = ListLoader<KinesisStreamSummary>()
    private var streams: [KinesisStreamSummary] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            streamListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            KinesisCreateStreamView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadStreams(force: true) }
        }
        .sheet(isPresented: $showPutRecordSheet) {
            if let stream = activeStream {
                KinesisPutRecordView(service: service, streamName: stream.streamName)
            }
        }
        .deleteConfirmation(items: $streamsToDelete, noun: "Stream") { items in
            if items.count == 1, let stream = items.first {
                Text("Are you sure you want to delete stream \"\(stream.streamName)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(items.count) streams?\n\nThis action cannot be undone.")
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
            case .createStream:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .putRecord:
                toolbarState.pendingAction = nil
                if activeStream != nil {
                    showPutRecordSheet = true
                }
            case .deleteStream:
                toolbarState.pendingAction = nil
                if let active = activeStream {
                    streamsToDelete = [active]
                }
            case .createDeliveryStream, .putFirehoseRecord, .deleteDeliveryStream:
                break
            }
        }
    }

    private var filteredStreams: [KinesisStreamSummary] {
        guard !searchText.isEmpty else { return streams }
        let query = searchText.lowercased()
        return streams.filter {
            $0.streamName.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var streamListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: streams.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading streams...", onRetry: { loadStreams(force: true) }) {
            VStack(spacing: 0) {
                if streams.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter streams")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedStreamIDs) {
                    if streams.isEmpty {
                        EmptyStateView(icon: "arrow.right.arrow.left.square", message: "No streams")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredStreams) { stream in
                    HStack {
                        Text(stream.streamName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        modeBadge(stream.streamMode)
                        statusBadge(stream.streamStatus)
                    }
                    .selectionForeground()
                    .tag(stream.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(stream.streamName) }
                        Button("Copy ARN") { copyToClipboard(stream.streamARN) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Stream") {
                                copyToClipboard(stream.describeStreamCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Streams") {
                                copyToClipboard(KinesisStreamSummary.listStreamsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Delete Stream") {
                                copyToClipboard(stream.deleteStreamCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Stream") {
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
                    Button("Create Stream") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: streams.count, selectedCount: selectedStreamIDs.count, noun: "stream")
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
        case "DELETING": .red
        case "UPDATING": .blue
        default: .gray
        }
    }

    private func modeBadge(_ mode: String) -> some View {
        StatusBadge(text: mode, color: modeColor(mode))
    }

    private func modeColor(_ mode: String) -> Color {
        switch mode {
        case "ON_DEMAND": .purple
        default: .gray
        }
    }

    // MARK: - Data

    private func loadStreams(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listStreams() },
            sort: { $0.streamName.localizedStandardCompare($1.streamName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreStreamName,
               let stream = items.first(where: { $0.streamName == savedName }) {
                selectedStreamIDs = [stream.id]
                activeStream = stream
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let stream = items.first(where: { $0.streamName == name }) {
                selectedStreamIDs = [stream.id]
                activeStream = stream
                pendingSelectName = nil
            }
        }
    }

    private func deleteStreams(_ targets: [KinesisStreamSummary]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteStream(name: $0.streamName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedStreamIDs.subtract(deleted)
                if let active = activeStream, deleted.contains(active.id) { activeStream = nil }
                loadStreams(force: true)
            }
        }
    }

}
