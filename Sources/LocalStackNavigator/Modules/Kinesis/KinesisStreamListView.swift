import SwiftUI
import AppKit

struct KinesisStreamListView: View {
    @ObservedObject var service: KinesisService
    @ObservedObject var toolbarState: KinesisToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedStreamIDs: Set<KinesisStreamSummary.ID>
    @Binding var activeStream: KinesisStreamSummary?
    var restoreStreamName: String?

    @State private var streams: [KinesisStreamSummary] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var streamsToDelete: [KinesisStreamSummary] = []
    @State private var showPutRecordSheet = false
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            streamListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            KinesisCreateStreamView(service: service)
                .onDisappear { loadStreams(force: true) }
        }
        .sheet(isPresented: $showPutRecordSheet) {
            if let stream = activeStream {
                KinesisPutRecordView(service: service, streamName: stream.streamName)
            }
        }
        .alert(
            streamsToDelete.count == 1
                ? "Delete Stream"
                : "Delete \(streamsToDelete.count) Streams",
            isPresented: Binding(
                get: { !streamsToDelete.isEmpty },
                set: { if !$0 { streamsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteStreams(streamsToDelete)
            }
            Button("Cancel", role: .cancel) {
                streamsToDelete = []
            }
        } message: {
            if streamsToDelete.count == 1, let stream = streamsToDelete.first {
                Text("Are you sure you want to delete stream \"\(stream.streamName)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(streamsToDelete.count) streams?\n\nThis action cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadStreams() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && streamsToDelete.isEmpty && !showPutRecordSheet && !isLoading }) {
            loadStreams(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedStreamIDs = []
            activeStream = nil
            streams = []
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

    @ViewBuilder
    private var streamListContent: some View {
        if isLoading && streams.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading streams...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, streams.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadStreams(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if streams.isEmpty {
            EmptyStateView(icon: "arrow.right.arrow.left.square", message: "No streams")
            .contextMenu {
                Button("Create Stream") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if streams.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter streams")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredStreams, selection: $selectedStreamIDs) { stream in
                    HStack {
                        Text(stream.streamName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        modeBadge(stream.streamMode)
                        statusBadge(stream.streamStatus)
                    }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Stream") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(streams.count) stream\(streams.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedStreamIDs.count > 1 {
                        Text("(\(selectedStreamIDs.count) selected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.listStreams()
                let freshStreams = loaded.sorted { $0.streamName.localizedStandardCompare($1.streamName) == .orderedAscending }
                if streams != freshStreams {
                    streams = freshStreams
                }
                if !hasRestoredSession, let savedName = restoreStreamName,
                   let stream = streams.first(where: { $0.streamName == savedName }) {
                    selectedStreamIDs = [stream.id]
                    activeStream = stream
                }
                hasRestoredSession = true
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func deleteStreams(_ targets: [KinesisStreamSummary]) {
        Task {
            var deletedIDs: Set<KinesisStreamSummary.ID> = []
            for stream in targets {
                do {
                    try await service.deleteStream(name: stream.streamName)
                    deletedIDs.insert(stream.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedStreamIDs.subtract(deletedIDs)
                if let active = activeStream, deletedIDs.contains(active.id) {
                    activeStream = nil
                }
                loadStreams(force: true)
            }
        }
    }
}
