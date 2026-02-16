import SwiftUI
import AppKit

struct DynamoDBTableListView: View {
    @ObservedObject var service: DynamoDBService
    @ObservedObject var toolbarState: DynamoDBToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTableIDs: Set<DynamoDBTable.ID>
    @Binding var activeTable: DynamoDBTable?
    @Binding var tableDetail: DynamoDBTableDetail?
    var restoreTableName: String?

    @State private var tables: [DynamoDBTable] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var tablesToDelete: [DynamoDBTable] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var tableToShowAttributes: DynamoDBTable?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            tableListHeader
            Divider()
            tableListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            DynamoDBCreateTableView(service: service, existingTableNames: Set(tables.map(\.tableName)))
                .onDisappear { loadTables(force: true) }
        }
        .alert(
            tablesToDelete.count == 1
                ? "Delete Table"
                : "Delete \(tablesToDelete.count) Tables",
            isPresented: Binding(
                get: { !tablesToDelete.isEmpty },
                set: { if !$0 { tablesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteTables(tablesToDelete)
            }
            Button("Cancel", role: .cancel) {
                tablesToDelete = []
            }
        } message: {
            if tablesToDelete.count == 1, let table = tablesToDelete.first {
                Text("Are you sure you want to delete \"\(table.tableName)\"?\n\nAll items in this table will be permanently deleted.")
            } else {
                let names = tablesToDelete.map(\.tableName).joined(separator: "\n")
                Text("Are you sure you want to delete these tables?\n\n\(names)\n\nAll items will be permanently deleted.")
            }
        }
        .sheet(item: $tableToShowAttributes) { table in
            DynamoDBTableAttributesView(service: service, table: table)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadTables() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && tablesToDelete.isEmpty && tableToShowAttributes == nil && !isLoading }) {
            loadTables(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedTableIDs = []
            activeTable = nil
            tableDetail = nil
            tables = []
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
        HStack {
            Text("Tables")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadTables(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadTables(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: tableDeleteDisabled, help: selectedTableIDs.count <= 1 ? "Delete Table" : "Delete \(selectedTableIDs.count) Tables") {
                tablesToDelete = tables.filter { selectedTableIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var tableListContent: some View {
        if isLoading && tables.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading tables...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, tables.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadTables(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tables.isEmpty {
            EmptyStateView(icon: "tablecells", message: "No tables")
            .contextMenu {
                Button("Create Table") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if tables.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter tables")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredTables, selection: $selectedTableIDs) { table in
                    Text(table.tableName)
                        .fontWeight(.medium)
                        .lineLimit(1)
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
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

                // Status bar
                Divider()
                HStack {
                    Text("\(tables.count) table\(tables.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedTableIDs.count > 1 {
                        Text("(\(selectedTableIDs.count) selected)")
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

    // MARK: - Data

    private func loadTables(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listTables()
                let freshTables = loaded.sorted { $0.tableName.localizedStandardCompare($1.tableName) == .orderedAscending }
                if tables != freshTables {
                    tables = freshTables
                }
                if !hasRestoredSession, let savedName = restoreTableName,
                   let table = tables.first(where: { $0.tableName == savedName }) {
                    selectedTableIDs = [table.id]
                    activeTable = table
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

    private func deleteTables(_ targets: [DynamoDBTable]) {
        Task {
            var deletedIDs: Set<DynamoDBTable.ID> = []
            for table in targets {
                do {
                    try await service.deleteTable(tableName: table.tableName)
                    deletedIDs.insert(table.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedTableIDs.subtract(deletedIDs)
                if let active = activeTable, deletedIDs.contains(active.id) {
                    activeTable = nil
                    tableDetail = nil
                }
                loadTables(force: true)
            }
        }
    }
}
