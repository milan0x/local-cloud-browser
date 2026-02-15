import SwiftUI
import AppKit

struct CloudWatchLogsStreamBrowserView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroup: CloudWatchLogGroup
    @ObservedObject var toolbarState: CloudWatchLogsToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var streams: [CloudWatchLogStream] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadTime: Date?
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    // Drill-down state
    @State private var activeStream: CloudWatchLogStream?

    // Sheets
    @State private var showDetailSheet = false
    @State private var showSearchSheet = false
    @State private var showCreateStreamSheet = false
    @State private var showPutEventSheet = false
    @State private var streamsToDelete: [CloudWatchLogStream] = []

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let stream = activeStream {
                eventViewerMode(stream: stream)
            } else {
                streamListMode
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            CloudWatchLogsGroupDetailView(logGroup: logGroup)
        }
        .sheet(isPresented: $showSearchSheet) {
            CloudWatchLogsSearchView(service: service, logGroup: logGroup)
        }
        .sheet(isPresented: $showCreateStreamSheet) {
            CloudWatchLogsCreateStreamView(
                service: service,
                logGroupName: logGroup.logGroupName,
                existingStreamNames: Set(streams.map(\.logStreamName))
            )
            .onDisappear { loadStreams(force: true) }
        }
        .alert(
            streamsToDelete.count == 1
                ? "Delete Log Stream"
                : "Delete \(streamsToDelete.count) Log Streams",
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
                Text("Are you sure you want to delete \"\(stream.logStreamName)\"?\n\nAll events in this stream will be permanently deleted.")
            } else {
                let names = streamsToDelete.map(\.logStreamName).joined(separator: "\n")
                Text("Are you sure you want to delete these log streams?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadStreams() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard activeStream == nil && !showCreateStreamSheet && streamsToDelete.isEmpty && !isLoading else { return }
            loadStreams(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .viewDetails:
                toolbarState.pendingAction = nil
                showDetailSheet = true
            case .search:
                toolbarState.pendingAction = nil
                showSearchSheet = true
            case .createLogGroup, .deleteSelected:
                break // handled by group list
            }
        }
    }

    private var filteredStreams: [CloudWatchLogStream] {
        guard !searchText.isEmpty else { return streams }
        let query = searchText.lowercased()
        return streams.filter { $0.logStreamName.lowercased().contains(query) }
    }

    // MARK: - Stream List Mode

    @ViewBuilder
    private var streamListMode: some View {
        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(logGroup.logGroupName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer()
            Button { showCreateStreamSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)
            .help("Create Log Stream")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()

        if isLoading && streams.isEmpty {
            ProgressView("Loading streams...")
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
            EmptyStateView(icon: "arrow.down.doc", message: "No log streams")
            .contextMenu {
                Button("Create Log Stream") {
                    showCreateStreamSheet = true
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
                List(filteredStreams) { stream in
                    Button {
                        activeStream = stream
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stream.logStreamName)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if let lastEvent = stream.lastEventTimestamp {
                                        Text(Self.timestampFormatter.string(from: lastEvent))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(stream.formattedStoredBytes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("View Events") {
                            activeStream = stream
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(stream.logStreamName) }
                        if let arn = stream.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Button("Copy as AWS CLI") {
                            copyToClipboard(stream.getLogEventsCLI(logGroupName: logGroup.logGroupName, endpointUrl: appState.endpoint, region: appState.region))
                        }
                        Divider()
                        Button("Create Log Stream") {
                            showCreateStreamSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Delete", role: .destructive) {
                            streamsToDelete = [stream]
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
                .contextMenu {
                    Button("Create Log Stream") {
                        showCreateStreamSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(streams.count) stream\(streams.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Event Viewer Mode

    @ViewBuilder
    private func eventViewerMode(stream: CloudWatchLogStream) -> some View {
        // Header with back button
        HStack {
            Button {
                activeStream = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Streams")
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(stream.logStreamName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button { showPutEventSheet = true } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)
            .help("Write Log Event")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        Divider()

        CloudWatchLogsEventListView(
            service: service,
            logGroupName: logGroup.logGroupName,
            logStreamName: stream.logStreamName
        )

        // Put event sheet
        EmptyView()
            .sheet(isPresented: $showPutEventSheet) {
                CloudWatchLogsPutEventView(
                    service: service,
                    logGroupName: logGroup.logGroupName,
                    logStreamName: stream.logStreamName
                )
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
                let loaded = try await service.describeLogStreams(logGroupName: logGroup.logGroupName)
                if streams != loaded {
                    streams = loaded
                }
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

    private func deleteStreams(_ targets: [CloudWatchLogStream]) {
        Task {
            for stream in targets {
                do {
                    try await service.deleteLogStream(logGroupName: logGroup.logGroupName, logStreamName: stream.logStreamName)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            loadStreams(force: true)
        }
    }
}
