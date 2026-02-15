import SwiftUI
import AppKit

struct KinesisFirehoseListView: View {
    @ObservedObject var service: KinesisFirehoseService
    @ObservedObject var toolbarState: KinesisToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedStreamIDs: Set<FirehoseDeliveryStreamSummary.ID>
    @Binding var activeStream: FirehoseDeliveryStreamSummary?
    var restoreDeliveryStreamName: String?

    @State private var streams: [FirehoseDeliveryStreamSummary] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var streamsToDelete: [FirehoseDeliveryStreamSummary] = []
    @State private var showPutRecordSheet = false
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            streamListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            KinesisFirehoseCreateView(service: service)
                .onDisappear { loadStreams(force: true) }
        }
        .sheet(isPresented: $showPutRecordSheet) {
            if let stream = activeStream {
                KinesisFirehosePutRecordView(service: service, deliveryStreamName: stream.deliveryStreamName)
            }
        }
        .alert(
            streamsToDelete.count == 1
                ? "Delete Delivery Stream"
                : "Delete \(streamsToDelete.count) Delivery Streams",
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
                Text("Are you sure you want to delete delivery stream \"\(stream.deliveryStreamName)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(streamsToDelete.count) delivery streams?\n\nThis action cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadStreams() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && streamsToDelete.isEmpty && !showPutRecordSheet && !isLoading else { return }
            loadStreams(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedStreamIDs = []
            activeStream = nil
            streams = []
            loadStreams(force: true)
        }
        .onChange(of: appState.region) {
            selectedStreamIDs = []
            activeStream = nil
            streams = []
            loadStreams(force: true)
        }
        .onChange(of: selectedStreamIDs) {
            if selectedStreamIDs.count == 1, let id = selectedStreamIDs.first {
                activeStream = streams.first { $0.id == id }
            } else {
                activeStream = nil
            }
        }
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

    @ViewBuilder
    private var streamListContent: some View {
        if isLoading && streams.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading delivery streams...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            VStack(spacing: 8) {
                Image(systemName: "flame")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No delivery streams")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Delivery Stream") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if streams.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter delivery streams")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredStreams, selection: $selectedStreamIDs) { stream in
                    HStack {
                        Text(stream.deliveryStreamName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        typeBadge(stream.deliveryStreamType)
                        statusBadge(stream.deliveryStreamStatus)
                    }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Delivery Stream") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(streams.count) delivery stream\(streams.count == 1 ? "" : "s")")
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
        Text(status)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
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
        Text(type)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(typeColor(type).opacity(0.15), in: Capsule())
            .foregroundStyle(typeColor(type))
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "KinesisStreamAsSource": .purple
        default: .gray
        }
    }

    private var connectionLostBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost — showing cached data")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
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
                let loaded = try await service.listDeliveryStreams()
                let freshStreams = loaded.sorted { $0.deliveryStreamName.localizedStandardCompare($1.deliveryStreamName) == .orderedAscending }
                if streams != freshStreams {
                    streams = freshStreams
                }
                if !hasRestoredSession, let savedName = restoreDeliveryStreamName,
                   let stream = streams.first(where: { $0.deliveryStreamName == savedName }) {
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

    private func deleteStreams(_ targets: [FirehoseDeliveryStreamSummary]) {
        Task {
            var deletedIDs: Set<FirehoseDeliveryStreamSummary.ID> = []
            for stream in targets {
                do {
                    try await service.deleteDeliveryStream(name: stream.deliveryStreamName)
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
