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
    @State private var gridColumns: [GridColumn] = []
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

    // Attributes sheet
    @State private var showAttributesSheet = false

    // Inline draft row
    @State private var isDraftRowActive = false
    @State private var saveDraftCounter = 0

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
        .sheet(isPresented: $showAttributesSheet) {
            DynamoDBTableAttributesView(service: service, table: table)
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
        .task {
            recomputeColumns()
            executeScan()
        }
        .onChange(of: items) { recomputeColumns() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard browseMode == .scan && !showPutItemSheet && editingItem == nil
                    && itemsToDelete.isEmpty && itemToShowDetail == nil && !isLoading
                    && !isDraftRowActive else { return }
            executeCurrentOperation(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .putItem:
                toolbarState.pendingAction = nil
                showPutItemSheet = true
            case .showAttributes:
                toolbarState.pendingAction = nil
                showAttributesSheet = true
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

                Button {
                    showAttributesSheet = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Table Attributes")

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
        if isLoading && items.isEmpty && !isDraftRowActive {
            ProgressView("Loading items...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, items.isEmpty && !isDraftRowActive {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { executeCurrentOperation(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty && !isDraftRowActive {
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
            DynamoDBItemGrid(
                columns: gridColumns,
                items: items,
                tableDetail: tableDetail,
                isReadOnly: appState.isReadOnly,
                selectedItemIDs: $selectedItemIDs,
                isDraftRowActive: isDraftRowActive,
                saveDraftCounter: saveDraftCounter,
                onSaveDraft: handleSaveDraft,
                onCancelDraft: { isDraftRowActive = false },
                onCellEdit: handleCellEdit,
                onViewDetail: { itemToShowDetail = $0 },
                onDeleteItems: { itemsToDelete = $0 },
                onEditComplex: { editingItem = $0 },
                onCopyJSON: { copyItemAsJSON($0) },
                onCopyGetItemCLI: { item in
                    copyToClipboard(item.getItemCLI(
                        tableName: table.tableName,
                        keySchema: tableDetail.keySchema,
                        endpointUrl: appState.endpoint,
                        region: appState.region
                    ))
                },
                onCopyPutItemCLI: { item in
                    copyToClipboard(item.putItemCLI(
                        tableName: table.tableName,
                        endpointUrl: appState.endpoint,
                        region: appState.region
                    ))
                },
                onPutItem: { showPutItemSheet = true }
            )
            .overlay(alignment: .bottom) {
                if errorMessage != nil && !items.isEmpty {
                    connectionLostBanner
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if isDraftRowActive {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("New item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("— ⌘S to save")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") {
                    isDraftRowActive = false
                }
                .font(.caption)
                Button {
                    saveDraftCounter += 1
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                }
                .keyboardShortcut("s")
                .disabled(appState.isReadOnly)
            } else {
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

    // MARK: - Inline Draft

    private func handleSaveDraft(_ values: [String: String]) {
        let pkName = tableDetail.partitionKey?.attributeName ?? ""
        let skName = tableDetail.sortKey?.attributeName

        // Validate keys
        guard let pkValue = values[pkName], !pkValue.isEmpty else {
            serviceError = ServiceError(code: "ValidationError", message: "Partition key (\(pkName)) is required.")
            return
        }
        if let skName, (values[skName] ?? "").isEmpty {
            serviceError = ServiceError(code: "ValidationError", message: "Sort key (\(skName)) is required.")
            return
        }

        // Build item
        var item: [String: AttributeValue] = [:]

        let pkType = tableDetail.attributeType(for: pkName) ?? "S"
        item[pkName] = pkType == "N" ? .number(pkValue) : .string(pkValue)

        if let skName, let skValue = values[skName], !skValue.isEmpty {
            let skType = tableDetail.attributeType(for: skName) ?? "S"
            item[skName] = skType == "N" ? .number(skValue) : .string(skValue)
        }

        for (key, value) in values {
            if key == pkName || key == skName { continue }
            if value.isEmpty { continue }
            item[key] = .string(value)
        }

        Task {
            do {
                try await service.putItem(tableName: table.tableName, item: item)
                isDraftRowActive = false
                executeCurrentOperation(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    // MARK: - Grid Support

    private func recomputeColumns() {
        gridColumns = computeGridColumns(items: items, tableDetail: tableDetail)
    }

    private func handleCellEdit(rowID: String, column: String, newValue: String) {
        guard let itemIndex = items.firstIndex(where: { stableItemID($0) == rowID }) else { return }
        let item = items[itemIndex]

        // Build updated attributes
        var updatedAttributes = item.attributes

        // Determine the type to preserve (or default to String for new attributes)
        let existingValue = item.attributes[column]
        let newAttributeValue: AttributeValue
        switch existingValue {
        case .number:
            newAttributeValue = .number(newValue)
        case .bool:
            newAttributeValue = .bool(newValue.lowercased() == "true")
        default:
            newAttributeValue = .string(newValue)
        }

        updatedAttributes[column] = newAttributeValue

        // Save via putItem (immediate save like TablePlus)
        Task {
            do {
                try await service.putItem(tableName: table.tableName, item: updatedAttributes)
                // Update local state
                items[itemIndex] = DynamoDBItem(attributes: updatedAttributes)
            } catch {
                serviceError = error.asServiceError
                // Refresh to revert to server state
                executeCurrentOperation(force: true)
            }
        }
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
}

