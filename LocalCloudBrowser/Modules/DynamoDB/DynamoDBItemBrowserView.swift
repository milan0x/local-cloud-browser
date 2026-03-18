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
    @State private var deleteTask: Task<Void, Never>?

    // Scan limit
    @State private var scanLimit = 50

    // Column sorting
    @State private var sortColumn: String?
    @State private var sortAscending = true

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

    /// Items sorted by current column sort, if any
    private var sortedItems: [DynamoDBItem] {
        guard let col = sortColumn else { return items }
        return items.sorted { a, b in
            let aVal = a.attributes[col]?.displayString ?? ""
            let bVal = b.attributes[col]?.displayString ?? ""
            // Try numeric comparison first
            if let aNum = Double(aVal), let bNum = Double(bVal) {
                return sortAscending ? aNum < bNum : aNum > bNum
            }
            return sortAscending ? aVal.localizedCompare(bVal) == .orderedAscending : aVal.localizedCompare(bVal) == .orderedDescending
        }
    }

    /// Validate that a value is a valid number string
    private func isValidNumber(_ value: String) -> Bool {
        Double(value) != nil || Decimal(string: value) != nil
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
        .onAutoRefresh(canRefresh: { browseMode == .scan && !showPutItemSheet && editingItem == nil
                    && itemsToDelete.isEmpty && itemToShowDetail == nil && !isLoading
                    && !isDraftRowActive }) {
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
                    if browseMode == .query {
                        // Validate number keys before executing
                        let pkType = tableDetail.attributeType(for: activePartitionKeyName)
                        if pkType == "N" && !isValidNumber(queryPartitionValue) {
                            serviceError = ServiceError(code: "ValidationError", message: "Partition key '\(activePartitionKeyName)' expects a number value.")
                            return
                        }
                        if let skName = activeSortKeyName, !querySortValue.isEmpty {
                            let skType = tableDetail.attributeType(for: skName)
                            if skType == "N" && !isValidNumber(querySortValue) {
                                serviceError = ServiceError(code: "ValidationError", message: "Sort key '\(skName)' expects a number value.")
                                return
                            }
                            if querySortOperator == .between && !querySortValue2.isEmpty && skType == "N" && !isValidNumber(querySortValue2) {
                                serviceError = ServiceError(code: "ValidationError", message: "Sort key '\(skName)' BETWEEN value 2 expects a number.")
                                return
                            }
                        }
                    }
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
                    .font(.caption)
                    .help("DynamoDB FilterExpression syntax, e.g. contains(#name, :val)")

                Text("Limit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $scanLimit) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("500").tag(500)
                }
                .labelsHidden()
                .frame(width: 65)
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
                    .font(.caption)

                if querySortOperator == .between {
                    Text("AND")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Value 2", text: $querySortValue2)
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
            EmptyStateView(icon: "tray", message: "No items")
            .contextMenu {
                Button("Put Item") { showPutItemSheet = true }
                    .disabled(appState.isReadOnly)
            }
        } else {
            DynamoDBItemGrid(
                columns: gridColumns,
                items: sortedItems,
                tableDetail: tableDetail,
                isReadOnly: appState.isReadOnly,
                selectedItemIDs: $selectedItemIDs,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                onSort: { column in
                    if sortColumn == column {
                        sortAscending.toggle()
                    } else {
                        sortColumn = column
                        sortAscending = true
                    }
                },
                isDraftRowActive: isDraftRowActive,
                saveDraftCounter: saveDraftCounter,
                onSaveDraft: handleSaveDraft,
                onCancelDraft: { isDraftRowActive = false },
                onCellEdit: handleCellEdit,
                onViewDetail: { itemToShowDetail = $0 },
                onDeleteItems: { itemsToDelete = $0 },
                onEditComplex: { editingItem = $0 },
                onCopyJSON: { copyItemAsJSON($0) },
                onCopyItemKey: { item in
                    let key = item.primaryKey(keySchema: tableDetail.keySchema)
                    let parts = key.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value.displayString)" }
                    copyToClipboard(parts.joined(separator: ", "))
                },
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
                    ConnectionLostBanner()
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
                Text("\(items.count)\(lastEvaluatedKey != nil ? "+" : "") items")
                    .font(.callout)
                    .foregroundStyle(.primary)
                if totalScanned > items.count {
                    Text("(\(totalScanned) scanned)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if selectedItemIDs.count > 1 {
                    Text("(\(selectedItemIDs.count) selected)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !items.isEmpty && selectedItemIDs.isEmpty && !isDraftRowActive {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Double-click to edit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if lastEvaluatedKey != nil {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            loadMoreItems()
                        } label: {
                            Label("Load More", systemImage: "arrow.down.circle")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Spacer()

                if !items.isEmpty {
                    Menu {
                        Button("Export as JSON") { exportAsJSON() }
                        Button("Export as CSV") { exportAsCSV() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.callout)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 80)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Export

    private func exportAsJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(table.tableName).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let jsonItems = items.map { $0.toJSON() }
            do {
                let data = try JSONSerialization.data(withJSONObject: jsonItems, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url)
            } catch {
                Log.error("Failed to export JSON to \(url.path): \(error.localizedDescription)", category: "DynamoDB")
            }
        }
    }

    private func exportAsCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(table.tableName).csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Collect all column names
            let allColumns = gridColumns.map(\.name)
            // Header
            var csv = allColumns.map { csvEscape($0) }.joined(separator: ",") + "\n"
            // Rows
            for item in items {
                let row = allColumns.map { col in
                    csvEscape(item.attributes[col]?.displayString ?? "")
                }.joined(separator: ",")
                csv += row + "\n"
            }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Log.error("Failed to export CSV to \(url.path): \(error.localizedDescription)", category: "DynamoDB")
            }
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
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
        let pkType = tableDetail.attributeType(for: pkName) ?? "S"
        if pkType == "N" && !isValidNumber(pkValue) {
            serviceError = ServiceError(code: "ValidationError", message: "Partition key (\(pkName)) expects a number value.")
            return
        }
        if let skName, (values[skName] ?? "").isEmpty {
            serviceError = ServiceError(code: "ValidationError", message: "Sort key (\(skName)) is required.")
            return
        }
        if let skName, let skValue = values[skName], !skValue.isEmpty {
            let skType = tableDetail.attributeType(for: skName) ?? "S"
            if skType == "N" && !isValidNumber(skValue) {
                serviceError = ServiceError(code: "ValidationError", message: "Sort key (\(skName)) expects a number value.")
                return
            }
        }

        // Build item
        var item: [String: AttributeValue] = [:]
        item[pkName] = pkType == "N" ? .number(pkValue) : .string(pkValue)

        if let skName, let skValue = values[skName], !skValue.isEmpty {
            let skTypeVal = tableDetail.attributeType(for: skName) ?? "S"
            item[skName] = skTypeVal == "N" ? .number(skValue) : .string(skValue)
        }

        for (key, value) in values {
            if key == pkName || key == skName { continue }
            if value.isEmpty { continue }
            // Infer type from existing items or schema
            let inferredType = inferAttributeType(for: key)
            switch inferredType {
            case "N":
                item[key] = .number(value)
            case "BOOL" where value.lowercased() == "true" || value.lowercased() == "false":
                item[key] = .bool(value.lowercased() == "true")
            default:
                item[key] = .string(value)
            }
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
                    limit: scanLimit,
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
                    limit: scanLimit,
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
        deleteTask?.cancel()
        deleteTask = Task {
            selectedItemIDs.subtract(Set(targets.map { stableItemID($0) }))
            var deletedKeys: Set<String> = []
            for item in targets {
                guard !Task.isCancelled else { break }
                let key = item.primaryKey(keySchema: tableDetail.keySchema)
                do {
                    try await service.deleteItem(tableName: table.tableName, key: key)
                    deletedKeys.insert(stableItemID(item))
                } catch {
                    if !Task.isCancelled { serviceError = error.asServiceError }
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

    /// Infer the DynamoDB type for a non-key attribute by checking existing items
    private func inferAttributeType(for key: String) -> String {
        // Check attribute definitions first (for key attributes)
        if let defType = tableDetail.attributeType(for: key) {
            return defType
        }
        // Look at existing items to infer type
        for item in items {
            if let value = item.attributes[key] {
                switch value {
                case .number: return "N"
                case .bool: return "BOOL"
                case .string: return "S"
                default: return "S"
                }
            }
        }
        return "S"
    }
}

