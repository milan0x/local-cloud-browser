import SwiftUI
import AppKit

struct DynamoDBTableListView: View {
    @ObservedObject var service: DynamoDBService
    @ObservedObject var toolbarState: DynamoDBToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedTableIDs: Set<DynamoDBTable.ID>
    @Binding var activeTable: DynamoDBTable?
    @Binding var tableDetail: DynamoDBTableDetail?
    var restoreTableName: String?

    @State private var showCreateSheet = false
    @State private var tablesToDelete: [DynamoDBTable] = []
    @State private var serviceError: ServiceError?
    @State private var tableToShowAttributes: DynamoDBTable?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = PaginatedListLoader<DynamoDBTable>()
    @StateObject private var recentDeletes = RecentDeletionTracker<String>()
    private var tables: [DynamoDBTable] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            tableListHeader
            Divider()
            tableListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            DynamoDBCreateTableView(service: service, existingTableNames: Set(tables.map(\.tableName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadTables(force: true) }
        }
        .deleteConfirmation(items: $tablesToDelete, noun: "Table") { items in
            if items.count == 1, let table = items.first {
                Text("Are you sure you want to delete \"\(table.tableName)\"?\n\nAll items in this table will be permanently deleted.")
            } else {
                let names = items.map(\.tableName).joined(separator: "\n")
                Text("Are you sure you want to delete these tables?\n\n\(names)\n\nAll items will be permanently deleted.")
            }
        } onDelete: { deleteTables($0) }
        .sheet(item: $tableToShowAttributes) { table in
            DynamoDBTableAttributesView(service: service, table: table)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadTables() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && tablesToDelete.isEmpty && tableToShowAttributes == nil && !loader.isLoading }) {
            loadTables(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedTableIDs = []
            activeTable = nil
            tableDetail = nil
            loader.items = []
            loadTables(force: true)
        }
        .syncSelection(selectedTableIDs, items: tables, activeItem: $activeTable)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createTable:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeTable {
                    tablesToDelete = [active]
                }
            case .showAttributes:
                toolbarState.pendingAction = nil
                if let active = activeTable {
                    tableToShowAttributes = active
                }
            case .putItem:
                break // handled by item browser
            }
        }
    }

    private var tableDeleteDisabled: Bool {
        appState.isReadOnly || selectedTableIDs.isEmpty
    }

    private var filteredTables: [DynamoDBTable] {
        guard !searchText.isEmpty else { return tables }
        let query = searchText.lowercased()
        return tables.filter { $0.tableName.lowercased().contains(query) }
    }

    // MARK: - Header

    private var tableListHeader: some View {
        ListHeaderBar(
            title: "Tables",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: tables.count,
            deleteDisabled: tableDeleteDisabled,
            deleteHelp: selectedTableIDs.count <= 1 ? "Delete Table" : "Delete \(selectedTableIDs.count) Tables",
            onRefresh: { loadTables(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { tablesToDelete = tables.filter { selectedTableIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var tableListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: tables.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading tables...", emptyIcon: "tablecells", emptyMessage: "No tables", onRetry: { loadTables(force: true) }) {
            VStack(spacing: 0) {
                if tables.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter tables")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedTableIDs) {
                    ForEach(filteredTables) { table in
                    Label(table.tableName, systemImage: "tablecells")
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .selectionForeground()
                        .tag(table.id)
                        .contextMenu {
                            Button("View Attributes") {
                                tableToShowAttributes = table
                            }
                            Divider()
                            Button("Copy Table Name") { copyToClipboard(table.tableName) }
                            Menu("Copy as AWS CLI") {
                                Button("Describe Table") {
                                    copyToClipboard(table.describeTableCLI(endpointUrl: appState.endpoint, region: appState.region))
                                }
                                Button("Scan") {
                                    copyToClipboard(table.scanTableCLI(endpointUrl: appState.endpoint, region: appState.region))
                                }
                            }
                            Divider()
                            Button("Create Table") {
                                showCreateSheet = true
                            }
                            .disabled(appState.isReadOnly)
                            Divider()
                            if selectedTableIDs.count > 1 && selectedTableIDs.contains(table.id) {
                                let selected = tables.filter { selectedTableIDs.contains($0.id) }
                                Button("Delete \(selected.count) Tables", role: .destructive) {
                                    tablesToDelete = selected
                                }
                                .disabled(appState.isReadOnly)
                            } else {
                                Button("Delete", role: .destructive) {
                                    tablesToDelete = [table]
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
                    Button("Create Table") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedTableIDs.count == 1,
                       let id = selectedTableIDs.first,
                       let table = tables.first(where: { $0.id == id }) {
                        tableToShowAttributes = table
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

                if filteredTables.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.tableName.lowercased().contains(query) }
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

                ListStatusBar(totalCount: tables.count, selectedCount: selectedTableIDs.count, noun: "table", hasMorePages: loader.hasMorePages)
            }
        }
    }

    // MARK: - Data

    private func loadTables(force: Bool = false, silent: Bool = false) {
        let recents = recentDeletes
        loader.load(force: force, silent: silent,
            fetch: { [service] token in
                let (items, next) = try await service.listTablesPage(token: token)
                let filtered = await recents.filter(items, by: \.tableName)
                return (filtered, next)
            },
            sort: { $0.tableName.localizedStandardCompare($1.tableName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreTableName,
               let table = items.first(where: { $0.tableName == savedName }) {
                selectedTableIDs = [table.id]
                activeTable = table
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let table = items.first(where: { $0.tableName == name }) {
                selectedTableIDs = [table.id]
                activeTable = table
                pendingSelectName = nil
            }
        }
    }

    private func deleteTables(_ targets: [DynamoDBTable]) {
        Task {
            selectedTableIDs.subtract(Set(targets.map(\.id)))
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteTable(tableName: $0.tableName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .dynamodb, by: deleted.count)
                selectedTableIDs.subtract(deleted)
                if let active = activeTable, deleted.contains(active.id) {
                    activeTable = nil
                    tableDetail = nil
                }
                // Eventual-consistency: DynamoDB ListTables can keep
                // returning a deleted table for several seconds. Track
                // the deleted names + remove from the visible list, so
                // the next reload doesn't resurrect them.
                let deletedNames = targets
                    .filter { deleted.contains($0.id) }
                    .map(\.tableName)
                recentDeletes.markDeleted(deletedNames)
                loader.items.removeAll { recentDeletes.contains($0.tableName) }
                loadTables(force: true)
            }
        }
    }

}
