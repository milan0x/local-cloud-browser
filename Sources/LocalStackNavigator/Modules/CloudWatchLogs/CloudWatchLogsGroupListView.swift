import SwiftUI
import AppKit

struct CloudWatchLogsGroupListView: View {
    @ObservedObject var service: CloudWatchLogsService
    @ObservedObject var toolbarState: CloudWatchLogsToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedLogGroupIDs: Set<CloudWatchLogGroup.ID>
    @Binding var activeLogGroup: CloudWatchLogGroup?
    var restoreLogGroupName: String?

    @State private var logGroups: [CloudWatchLogGroup] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var logGroupsToDelete: [CloudWatchLogGroup] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var logGroupToShowDetail: CloudWatchLogGroup?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            logGroupListHeader
            Divider()
            logGroupListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            CloudWatchLogsCreateGroupView(service: service, existingGroupNames: Set(logGroups.map(\.logGroupName)))
                .onDisappear { loadLogGroups(force: true) }
        }
        .alert(
            logGroupsToDelete.count == 1
                ? "Delete Log Group"
                : "Delete \(logGroupsToDelete.count) Log Groups",
            isPresented: Binding(
                get: { !logGroupsToDelete.isEmpty },
                set: { if !$0 { logGroupsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteLogGroups(logGroupsToDelete)
            }
            Button("Cancel", role: .cancel) {
                logGroupsToDelete = []
            }
        } message: {
            if logGroupsToDelete.count == 1, let group = logGroupsToDelete.first {
                Text("Are you sure you want to delete \"\(group.logGroupName)\"?\n\nAll log streams and events in this group will be permanently deleted.")
            } else {
                let names = logGroupsToDelete.map(\.logGroupName).joined(separator: "\n")
                Text("Are you sure you want to delete these log groups?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $logGroupToShowDetail) { logGroup in
            CloudWatchLogsGroupDetailView(logGroup: logGroup)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadLogGroups() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && logGroupsToDelete.isEmpty && logGroupToShowDetail == nil && !isLoading else { return }
            loadLogGroups(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedLogGroupIDs = []
            activeLogGroup = nil
            logGroups = []
            loadLogGroups(force: true)
        }
        .onChange(of: appState.region) {
            selectedLogGroupIDs = []
            activeLogGroup = nil
            logGroups = []
            loadLogGroups(force: true)
        }
        .onChange(of: selectedLogGroupIDs) {
            if selectedLogGroupIDs.count == 1, let id = selectedLogGroupIDs.first {
                activeLogGroup = logGroups.first { $0.id == id }
            } else {
                activeLogGroup = nil
            }
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createLogGroup:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeLogGroup {
                    logGroupsToDelete = [active]
                }
            case .viewDetails, .search:
                break // handled by stream browser
            }
        }
    }

    private var logGroupDeleteDisabled: Bool {
        appState.isReadOnly || selectedLogGroupIDs.isEmpty
    }

    private var filteredLogGroups: [CloudWatchLogGroup] {
        guard !searchText.isEmpty else { return logGroups }
        let query = searchText.lowercased()
        return logGroups.filter { $0.logGroupName.lowercased().contains(query) }
    }

    // MARK: - Header

    private var logGroupListHeader: some View {
        HStack {
            Text("Log Groups")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadLogGroups(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadLogGroups(force: true)
            }

            Button {
                logGroupsToDelete = logGroups.filter { selectedLogGroupIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(logGroupDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(logGroupDeleteDisabled)
            .help(selectedLogGroupIDs.count <= 1 ? "Delete Log Group" : "Delete \(selectedLogGroupIDs.count) Log Groups")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var logGroupListContent: some View {
        if isLoading && logGroups.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading log groups...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, logGroups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadLogGroups(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if logGroups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No log groups")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Log Group") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if logGroups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter log groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredLogGroups, selection: $selectedLogGroupIDs) { logGroup in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(logGroup.logGroupName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let retention = logGroup.retentionInDays {
                                Text("\(retention)d")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            Text(logGroup.formattedStoredBytes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(logGroup.id)
                    .contextMenu {
                        Button("View Details") {
                            logGroupToShowDetail = logGroup
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(logGroup.logGroupName) }
                        if let arn = logGroup.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Log Groups") {
                                copyToClipboard(logGroup.describeLogGroupsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Describe Log Streams") {
                                copyToClipboard(logGroup.describeLogStreamsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Log Group") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedLogGroupIDs.count > 1 && selectedLogGroupIDs.contains(logGroup.id) {
                            let selected = logGroups.filter { selectedLogGroupIDs.contains($0.id) }
                            Button("Delete \(selected.count) Log Groups", role: .destructive) {
                                logGroupsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                logGroupsToDelete = [logGroup]
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
                    Button("Create Log Group") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedLogGroupIDs.count == 1,
                       let id = selectedLogGroupIDs.first,
                       let logGroup = logGroups.first(where: { $0.id == id }) {
                        logGroupToShowDetail = logGroup
                    }
                })

                // Status bar
                Divider()
                HStack {
                    Text("\(logGroups.count) log group\(logGroups.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedLogGroupIDs.count > 1 {
                        Text("(\(selectedLogGroupIDs.count) selected)")
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

    private func loadLogGroups(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.describeLogGroups()
                let freshGroups = loaded.sorted { $0.logGroupName.localizedStandardCompare($1.logGroupName) == .orderedAscending }
                if logGroups != freshGroups {
                    logGroups = freshGroups
                }
                if !hasRestoredSession, let savedName = restoreLogGroupName,
                   let logGroup = logGroups.first(where: { $0.logGroupName == savedName }) {
                    selectedLogGroupIDs = [logGroup.id]
                    activeLogGroup = logGroup
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

    private func deleteLogGroups(_ targets: [CloudWatchLogGroup]) {
        Task {
            var deletedIDs: Set<CloudWatchLogGroup.ID> = []
            for logGroup in targets {
                do {
                    try await service.deleteLogGroup(name: logGroup.logGroupName)
                    deletedIDs.insert(logGroup.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedLogGroupIDs.subtract(deletedIDs)
                if let active = activeLogGroup, deletedIDs.contains(active.id) {
                    activeLogGroup = nil
                }
                loadLogGroups(force: true)
            }
        }
    }
}
