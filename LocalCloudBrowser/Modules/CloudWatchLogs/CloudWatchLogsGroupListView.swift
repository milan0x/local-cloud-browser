import SwiftUI
import AppKit

struct CloudWatchLogsGroupListView: View {
    @ObservedObject var service: CloudWatchLogsService
    @ObservedObject var toolbarState: CloudWatchLogsToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedLogGroupIDs: Set<CloudWatchLogGroup.ID>
    @Binding var activeLogGroup: CloudWatchLogGroup?
    var restoreLogGroupName: String?

    @State private var showCreateSheet = false
    @State private var logGroupsToDelete: [CloudWatchLogGroup] = []
    @State private var serviceError: ServiceError?
    @State private var logGroupToShowDetail: CloudWatchLogGroup?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = PaginatedListLoader<CloudWatchLogGroup>()
    private var logGroups: [CloudWatchLogGroup] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            logGroupListHeader
            Divider()
            logGroupListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            CloudWatchLogsCreateGroupView(service: service, existingGroupNames: Set(logGroups.map(\.logGroupName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadLogGroups(force: true) }
        }
        .deleteConfirmation(items: $logGroupsToDelete, noun: "Log Group") { items in
            if items.count == 1, let group = items.first {
                Text("Are you sure you want to delete \"\(group.logGroupName)\"?\n\nAll log streams and events in this group will be permanently deleted.")
            } else {
                let names = items.map(\.logGroupName).joined(separator: "\n")
                Text("Are you sure you want to delete these log groups?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteLogGroups($0) }
        .sheet(item: $logGroupToShowDetail) { logGroup in
            CloudWatchLogsGroupDetailView(logGroup: logGroup)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadLogGroups() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && logGroupsToDelete.isEmpty && logGroupToShowDetail == nil && !loader.isLoading }) {
            loadLogGroups(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedLogGroupIDs = []
            activeLogGroup = nil
            loader.items = []
            loadLogGroups(force: true)
        }
        .syncSelection(selectedLogGroupIDs, items: logGroups, activeItem: $activeLogGroup)
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
        ListHeaderBar(
            title: "Log Groups",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: logGroups.count,
            deleteDisabled: logGroupDeleteDisabled,
            deleteHelp: selectedLogGroupIDs.count <= 1 ? "Delete Log Group" : "Delete \(selectedLogGroupIDs.count) Log Groups",
            onRefresh: { loadLogGroups(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { logGroupsToDelete = logGroups.filter { selectedLogGroupIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var logGroupListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: logGroups.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading log groups...", emptyIcon: "doc.text.magnifyingglass", emptyMessage: "No log groups", onRetry: { loadLogGroups(force: true) }) {
            VStack(spacing: 0) {
                if logGroups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter log groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedLogGroupIDs) {
                    ForEach(filteredLogGroups) { logGroup in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(logGroup.logGroupName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let retention = logGroup.retentionInDays {
                                StatusBadge(text: "\(retention)d", color: .blue)
                            }
                            Text(logGroup.formattedStoredBytes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .selectionForeground()
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
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
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

                if filteredLogGroups.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.logGroupName.lowercased().contains(query) }
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

                ListStatusBar(totalCount: logGroups.count, selectedCount: selectedLogGroupIDs.count, noun: "log group", hasMorePages: loader.hasMorePages)
            }
        }
    }

    // MARK: - Data

    private func loadLogGroups(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.describeLogGroupsPage(token: token) },
            sort: { $0.logGroupName.localizedStandardCompare($1.logGroupName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreLogGroupName,
               let logGroup = items.first(where: { $0.logGroupName == savedName }) {
                selectedLogGroupIDs = [logGroup.id]
                activeLogGroup = logGroup
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let logGroup = items.first(where: { $0.logGroupName == name }) {
                selectedLogGroupIDs = [logGroup.id]
                activeLogGroup = logGroup
                pendingSelectName = nil
            }
        }
    }

    private func deleteLogGroups(_ targets: [CloudWatchLogGroup]) {
        Task {
            selectedLogGroupIDs.subtract(Set(targets.map(\.id)))
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteLogGroup(name: $0.logGroupName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .cloudwatchLogs, by: deleted.count)
                selectedLogGroupIDs.subtract(deleted)
                if let active = activeLogGroup, deleted.contains(active.id) {
                    activeLogGroup = nil
                }
                loadLogGroups(force: true)
            }
        }
    }
}
