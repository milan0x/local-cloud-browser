import SwiftUI
import AppKit

struct CloudWatchLogsStreamBrowserView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroup: CloudWatchLogGroup
    @ObservedObject var toolbarState: CloudWatchLogsToolbarState
    @EnvironmentObject private var appState: AppState

    @StateObject private var loader = PaginatedListLoader<CloudWatchLogStream>()
    private var streams: [CloudWatchLogStream] { loader.items }
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
        .onAutoRefresh(canRefresh: { activeStream == nil && !showCreateStreamSheet && streamsToDelete.isEmpty && !loader.isLoading }) {
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
            ListHeaderButton("plus", isDisabled: appState.isReadOnly, help: "Create Log Stream") {
                showCreateStreamSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()

        if loader.isLoading && streams.isEmpty {
            ProgressView("Loading streams...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = loader.errorMessage, streams.isEmpty {
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
                            loader.searchAll { $0.logStreamName.lowercased().contains(query) }
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

                ListStatusBar(totalCount: streams.count, selectedCount: 0, noun: "stream", hasMorePages: loader.hasMorePages)
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
        loader.load(force: force, silent: silent,
            fetch: { [service, logGroup] token in try await service.describeLogStreamsPage(logGroupName: logGroup.logGroupName, token: token) },
            sort: { ($0.lastEventTimestamp ?? .distantPast) > ($1.lastEventTimestamp ?? .distantPast) }
        )
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
