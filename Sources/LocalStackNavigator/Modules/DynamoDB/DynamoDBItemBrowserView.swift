import SwiftUI
import AppKit

struct DynamoDBItemBrowserView: View {
    @ObservedObject var service: DynamoDBService
    @ObservedObject var toolbarState: DynamoDBToolbarState
    @EnvironmentObject private var appState: AppState
    let table: DynamoDBTable
    let tableDetail: DynamoDBTableDetail

    // Item state
    @State private var items: [DynamoDBItem] = []
    @State private var selectedItemIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastEvaluatedKey: [String: Any]?
    @State private var totalScanned = 0
    @State private var lastLoadTime: Date?

    // Browse mode
    @State private var browseMode: BrowseMode = .scan
    @State private var filterExpression = ""

    // Query state
    @State private var queryPartitionValue = ""
    @State private var querySortOperator: SortKeyOperator = .equals
    @State private var querySortValue = ""
    @State private var querySortValue2 = "" // for BETWEEN
    @State private var selectedIndexName: String?

    // Sheets
    @State private var itemToShowDetail: DynamoDBItem?
    @State private var showPutItemSheet = false
    @State private var editingItem: DynamoDBItem?
    @State private var itemsToDelete: [DynamoDBItem] = []
    @State private var serviceError: ServiceError?

    enum BrowseMode: String, CaseIterable {
        case scan = "Scan"
        case query = "Query"
    }

    enum SortKeyOperator: String, CaseIterable {
        case equals = "="
        case lessThan = "<"
        case greaterThan = ">"
        case lessOrEqual = "<="
        case greaterOrEqual = ">="
        case beginsWith = "begins_with"
        case between = "BETWEEN"
    }

    private var keyNames: [String] {
        tableDetail.keySchema.map(\.attributeName)
    }

    private var partitionKeyName: String {
        tableDetail.partitionKey?.attributeName ?? ""
    }

    private var sortKeyName: String? {
        tableDetail.sortKey?.attributeName
    }

    /// The active key schema — uses index key schema if a secondary index is selected
    private var activeKeySchema: [KeySchemaElement] {
        if let indexName = selectedIndexName {
            if let gsi = tableDetail.globalSecondaryIndexes.first(where: { $0.indexName == indexName }) {
                return gsi.keySchema
            }
            if let lsi = tableDetail.localSecondaryIndexes.first(where: { $0.indexName == indexName }) {
                return lsi.keySchema
            }
        }
        return tableDetail.keySchema
    }

    private var activePartitionKeyName: String {
        activeKeySchema.first { $0.keyType == "HASH" }?.attributeName ?? partitionKeyName
    }

    private var activeSortKeyName: String? {
        activeKeySchema.first { $0.keyType == "RANGE" }?.attributeName
    }

    /// Stable item ID using the table's primary key (always, even when querying by index)
    private func stableItemID(_ item: DynamoDBItem) -> String {
        item.id(keySchema: tableDetail.keySchema)
    }

    var body: some View {
        VStack(spacing: 0) {
            queryControls
            Divider()
            itemTable
            Divider()
            statusBar
        }
        .sheet(item: $itemToShowDetail) { item in
            DynamoDBItemDetailView(
                item: item,
                tableDetail: tableDetail,
                tableName: table.tableName,
                onEdit: { editingItem = $0 },
                onDelete: { itemsToDelete = [$0] }
            )
        }
        .sheet(isPresented: $showPutItemSheet) {
            DynamoDBPutItemView(
                service: service,
                tableDetail: tableDetail,
                editingItem: nil
            )
            .onDisappear { executeCurrentOperation(force: true) }
        }
        .sheet(item: $editingItem) { item in
            DynamoDBPutItemView(
                service: service,
                tableDetail: tableDetail,
                editingItem: item
            )
            .onDisappear { executeCurrentOperation(force: true) }
        }
        .alert(
            itemsToDelete.count == 1 ? "Delete Item" : "Delete \(itemsToDelete.count) Items",
            isPresented: Binding(
                get: { !itemsToDelete.isEmpty },
                set: { if !$0 { itemsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteItems(itemsToDelete)
            }
            Button("Cancel", role: .cancel) {
                itemsToDelete = []
            }
        } message: {
            if itemsToDelete.count == 1 {
                Text("Are you sure you want to delete this item?\n\nThis cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(itemsToDelete.count) items?\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { executeScan() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard browseMode == .scan && !showPutItemSheet && editingItem == nil
                    && itemsToDelete.isEmpty && itemToShowDetail == nil && !isLoading else { return }
            executeCurrentOperation(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .putItem:
                toolbarState.pendingAction = nil
                showPutItemSheet = true
            case .showAttributes:
                break // handled by table list
            case .createTable:
                break // handled by table list
            case .deleteSelected:
                break // handled by table list
            }
        }
    }

    // MARK: - Query Controls

    private var queryControls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Mode", selection: $browseMode) {
                    ForEach(BrowseMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button("Execute") {
                    executeCurrentOperation(force: true)
                }
                .disabled(browseMode == .query && queryPartitionValue.isEmpty)
            }

            if browseMode == .query {
                queryInputs
            }

            HStack {
                Text("Filter:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Filter expression (optional)", text: $filterExpression)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var queryInputs: some View {
        // Index picker (if GSIs or LSIs exist)
        if !tableDetail.globalSecondaryIndexes.isEmpty || !tableDetail.localSecondaryIndexes.isEmpty {
            HStack {
                Text("Index:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Index", selection: $selectedIndexName) {
                    Text("Primary Key").tag(nil as String?)
                    ForEach(tableDetail.globalSecondaryIndexes) { gsi in
                        Text("\(gsi.indexName) (GSI)").tag(gsi.indexName as String?)
                    }
                    ForEach(tableDetail.localSecondaryIndexes) { lsi in
                        Text("\(lsi.indexName) (LSI)").tag(lsi.indexName as String?)
                    }
                }
                .labelsHidden()
            }
        }

        HStack {
            Text("\(activePartitionKeyName) =")
                .font(.caption)
                .fontWeight(.medium)
            TextField("Partition key value", text: $queryPartitionValue)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }

        if let skName = activeSortKeyName {
            HStack {
                Text(skName)
                    .font(.caption)
                    .fontWeight(.medium)
                Picker("", selection: $querySortOperator) {
                    ForEach(SortKeyOperator.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                TextField("Sort key value", text: $querySortValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                if querySortOperator == .between {
                    Text("AND")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Value 2", text: $querySortValue2)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Item Table

    @ViewBuilder
    private var itemTable: some View {
        if isLoading && items.isEmpty {
            ProgressView("Loading items...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { executeCurrentOperation(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No items")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Put Item") { showPutItemSheet = true }
                    .disabled(appState.isReadOnly)
            }
        } else {
            itemTableContent
        }
    }

    @ViewBuilder
    private var itemTableContent: some View {
        if sortKeyName != nil {
            itemTableWithSortKey
        } else {
            itemTableWithoutSortKey
        }
    }

    private var itemTableWithSortKey: some View {
        Table(items, selection: $selectedItemIDs) {
            TableColumn(partitionKeyName) { item in
                Text(item.keyValue(for: partitionKeyName))
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 150)

            TableColumn(sortKeyName ?? "") { item in
                Text(item.keyValue(for: sortKeyName ?? ""))
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Attributes") { item in
                Text(item.attributesPreview(excluding: keyNames))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 200)

            TableColumn("Actions") { item in
                itemActionsRow(item)
            }
            .width(min: 80, ideal: 100)
        }
        .modifier(ItemTableContextMenuModifier(
            items: items,
            stableItemID: stableItemID,
            table: table,
            tableDetail: tableDetail,
            appState: appState,
            itemToShowDetail: $itemToShowDetail,
            editingItem: $editingItem,
            itemsToDelete: $itemsToDelete,
            showPutItemSheet: $showPutItemSheet,
            copyItemAsJSON: copyItemAsJSON,
            copyToClipboard: copyToClipboard
        ))
        .overlay(alignment: .bottom) {
            if errorMessage != nil && !items.isEmpty {
                connectionLostBanner
            }
        }
    }

    private var itemTableWithoutSortKey: some View {
        Table(items, selection: $selectedItemIDs) {
            TableColumn(partitionKeyName) { item in
                Text(item.keyValue(for: partitionKeyName))
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Attributes") { item in
                Text(item.attributesPreview(excluding: keyNames))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 200)

            TableColumn("Actions") { item in
                itemActionsRow(item)
            }
            .width(min: 80, ideal: 100)
        }
        .modifier(ItemTableContextMenuModifier(
            items: items,
            stableItemID: stableItemID,
            table: table,
            tableDetail: tableDetail,
            appState: appState,
            itemToShowDetail: $itemToShowDetail,
            editingItem: $editingItem,
            itemsToDelete: $itemsToDelete,
            showPutItemSheet: $showPutItemSheet,
            copyItemAsJSON: copyItemAsJSON,
            copyToClipboard: copyToClipboard
        ))
        .overlay(alignment: .bottom) {
            if errorMessage != nil && !items.isEmpty {
                connectionLostBanner
            }
        }
    }

    private func itemActionsRow(_ item: DynamoDBItem) -> some View {
        HStack(spacing: 8) {
            Button {
                itemToShowDetail = item
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help("View Details")

            Button {
                copyItemAsJSON(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy as JSON")

            Button(role: .destructive) {
                itemsToDelete = [item]
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(appState.isReadOnly ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
            .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("Items: \(items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if totalScanned > items.count {
                Text("Scanned: \(totalScanned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectedItemIDs.count > 1 {
                Text("(\(selectedItemIDs.count) selected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if lastEvaluatedKey != nil {
                Button("Load More") {
                    loadMoreItems()
                }
                .font(.caption)
                .disabled(isLoading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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

    // MARK: - Data Operations

    private func executeCurrentOperation(force: Bool = false, silent: Bool = false) {
        switch browseMode {
        case .scan: executeScan(force: force, silent: silent)
        case .query: executeQuery(force: force, silent: silent)
        }
    }

    private func executeScan(force: Bool = false, silent: Bool = false, startKey: [String: Any]? = nil) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let result = try await service.scan(
                    tableName: table.tableName,
                    exclusiveStartKey: startKey,
                    filterExpression: filterExpression.isEmpty ? nil : filterExpression
                )
                if startKey != nil {
                    items.append(contentsOf: result.items)
                } else {
                    items = result.items
                }
                selectedItemIDs = []
                totalScanned = (startKey != nil ? totalScanned : 0) + result.scannedCount
                lastEvaluatedKey = result.lastEvaluatedKey
            } catch {
                if !silent { errorMessage = error.localizedDescription }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func executeQuery(force: Bool = false, silent: Bool = false, startKey: [String: Any]? = nil) {
        guard !queryPartitionValue.isEmpty else { return }
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 { return }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let pkAttrType = tableDetail.attributeType(for: activePartitionKeyName) ?? "S"
                var keyCondition = "#pk = :pkval"
                var exprValues: [String: Any] = [
                    ":pkval": attributeValueJSON(queryPartitionValue, type: pkAttrType),
                ]
                var exprNames: [String: String] = ["#pk": activePartitionKeyName]

                if let skName = activeSortKeyName, !querySortValue.isEmpty {
                    let skAttrType = tableDetail.attributeType(for: skName) ?? "S"
                    exprNames["#sk"] = skName

                    switch querySortOperator {
                    case .equals:
                        keyCondition += " AND #sk = :skval"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .lessThan:
                        keyCondition += " AND #sk < :skval"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .greaterThan:
                        keyCondition += " AND #sk > :skval"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .lessOrEqual:
                        keyCondition += " AND #sk <= :skval"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .greaterOrEqual:
                        keyCondition += " AND #sk >= :skval"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .beginsWith:
                        keyCondition += " AND begins_with(#sk, :skval)"
                        exprValues[":skval"] = attributeValueJSON(querySortValue, type: skAttrType)
                    case .between:
                        keyCondition += " AND #sk BETWEEN :skval1 AND :skval2"
                        exprValues[":skval1"] = attributeValueJSON(querySortValue, type: skAttrType)
                        exprValues[":skval2"] = attributeValueJSON(querySortValue2, type: skAttrType)
                    }
                }

                let result = try await service.query(
                    tableName: table.tableName,
                    keyConditionExpression: keyCondition,
                    expressionAttributeValues: exprValues,
                    expressionAttributeNames: exprNames,
                    indexName: selectedIndexName,
                    exclusiveStartKey: startKey,
                    filterExpression: filterExpression.isEmpty ? nil : filterExpression
                )
                if startKey != nil {
                    items.append(contentsOf: result.items)
                } else {
                    items = result.items
                }
                selectedItemIDs = []
                totalScanned = (startKey != nil ? totalScanned : 0) + result.scannedCount
                lastEvaluatedKey = result.lastEvaluatedKey
            } catch {
                if !silent { errorMessage = error.localizedDescription }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func loadMoreItems() {
        guard let startKey = lastEvaluatedKey else { return }
        switch browseMode {
        case .scan: executeScan(force: true, startKey: startKey)
        case .query: executeQuery(force: true, startKey: startKey)
        }
    }

    private func deleteItems(_ targets: [DynamoDBItem]) {
        Task {
            var deletedKeys: Set<String> = []
            for item in targets {
                let key = item.primaryKey(keySchema: tableDetail.keySchema)
                do {
                    try await service.deleteItem(tableName: table.tableName, key: key)
                    deletedKeys.insert(stableItemID(item))
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedKeys.isEmpty {
                items.removeAll { deletedKeys.contains(stableItemID($0)) }
                selectedItemIDs.subtract(deletedKeys)
            }
        }
    }

    /// Build DynamoDB typed JSON for a value: `{"S": "value"}` or `{"N": "123"}`
    private func attributeValueJSON(_ value: String, type: String) -> [String: Any] {
        [type: value]
    }

    private func copyItemAsJSON(_ item: DynamoDBItem) {
        copyToClipboard(item.toDisplayJSON())
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Shared context menu modifier for item tables

private struct ItemTableContextMenuModifier: ViewModifier {
    let items: [DynamoDBItem]
    let stableItemID: (DynamoDBItem) -> String
    let table: DynamoDBTable
    let tableDetail: DynamoDBTableDetail
    let appState: AppState
    @Binding var itemToShowDetail: DynamoDBItem?
    @Binding var editingItem: DynamoDBItem?
    @Binding var itemsToDelete: [DynamoDBItem]
    @Binding var showPutItemSheet: Bool
    let copyItemAsJSON: (DynamoDBItem) -> Void
    let copyToClipboard: (String) -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let id = ids.first,
                   let item = items.first(where: { stableItemID($0) == id }) {
                    Button("View Details") { itemToShowDetail = item }
                    Divider()
                    Button("Copy as JSON") { copyItemAsJSON(item) }
                    Menu("Copy as AWS CLI") {
                        Button("Get Item") {
                            copyToClipboard(item.getItemCLI(
                                tableName: table.tableName,
                                keySchema: tableDetail.keySchema,
                                endpointUrl: appState.endpoint,
                                region: appState.region
                            ))
                        }
                        Button("Put Item") {
                            copyToClipboard(item.putItemCLI(
                                tableName: table.tableName,
                                endpointUrl: appState.endpoint,
                                region: appState.region
                            ))
                        }
                    }
                    Divider()
                    Button("Edit") { editingItem = item }
                        .disabled(appState.isReadOnly)
                    Button("Delete", role: .destructive) { itemsToDelete = [item] }
                        .disabled(appState.isReadOnly)
                } else if ids.count > 1 {
                    let selected = items.filter { ids.contains(stableItemID($0)) }
                    Button("Delete \(selected.count) Items", role: .destructive) {
                        itemsToDelete = selected
                    }
                    .disabled(appState.isReadOnly)
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first,
                   let item = items.first(where: { stableItemID($0) == id }) {
                    itemToShowDetail = item
                }
            }
            .contextMenu {
                Button("Put Item") { showPutItemSheet = true }
                    .disabled(appState.isReadOnly)
            }
    }
}

