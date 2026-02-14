import SwiftUI

struct DynamoDBPutItemView: View {
    @ObservedObject var service: DynamoDBService
    let tableDetail: DynamoDBTableDetail
    let editingItem: DynamoDBItem?
    @Environment(\.dismiss) private var dismiss

    @State private var partitionKeyValue = ""
    @State private var sortKeyValue = ""
    @State private var attributeRows: [AttributeRow] = []
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    struct AttributeRow: Identifiable {
        let id = UUID()
        var name: String
        var value: String
        var type: AttributeValueType
    }

    enum AttributeValueType: String, CaseIterable {
        case string = "String"
        case number = "Number"
        case bool = "Boolean"
        case null = "Null"
        case list = "List (JSON)"
        case map = "Map (JSON)"
        case stringSet = "String Set"
        case numberSet = "Number Set"

        var typeCode: String {
            switch self {
            case .string: "S"
            case .number: "N"
            case .bool: "BOOL"
            case .null: "NULL"
            case .list: "L"
            case .map: "M"
            case .stringSet: "SS"
            case .numberSet: "NS"
            }
        }
    }

    private var isEditing: Bool { editingItem != nil }

    private var partitionKeyName: String {
        tableDetail.partitionKey?.attributeName ?? ""
    }

    private var partitionKeyType: String {
        tableDetail.attributeType(for: partitionKeyName) ?? "S"
    }

    private var sortKeyName: String? {
        tableDetail.sortKey?.attributeName
    }

    private var sortKeyType: String? {
        guard let name = sortKeyName else { return nil }
        return tableDetail.attributeType(for: name) ?? "S"
    }

    private func typeDisplayName(_ type: String) -> String {
        switch type {
        case "S": "String"
        case "N": "Number"
        case "B": "Binary"
        default: type
        }
    }

    init(service: DynamoDBService, tableDetail: DynamoDBTableDetail, editingItem: DynamoDBItem?) {
        self.service = service
        self.tableDetail = tableDetail
        self.editingItem = editingItem

        if let item = editingItem {
            let keyNames = Set(tableDetail.keySchema.map(\.attributeName))
            _partitionKeyValue = State(initialValue: item.keyValue(for: tableDetail.partitionKey?.attributeName ?? ""))
            if let skName = tableDetail.sortKey?.attributeName {
                _sortKeyValue = State(initialValue: item.keyValue(for: skName))
            }

            let rows = item.attributes
                .filter { !keyNames.contains($0.key) }
                .sorted { $0.key < $1.key }
                .map { key, value -> AttributeRow in
                    let (typeEnum, stringValue) = Self.decomposeAttributeValue(value)
                    return AttributeRow(name: key, value: stringValue, type: typeEnum)
                }
            _attributeRows = State(initialValue: rows)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                primaryKeySection
                attributeSections
            }
            .formStyle(.grouped)

            if let validationError {
                Text(validationError)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Update" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 560)
        .frame(minHeight: 450)
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Primary Key Section

    private var primaryKeySection: some View {
        Section("Primary Key") {
            LabeledContent {
                TextField("", text: $partitionKeyValue, prompt: Text("Enter value"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing)
            } label: {
                HStack(spacing: 6) {
                    Text(partitionKeyName)
                    keyTypeBadge(partitionKeyType)
                }
            }
            if let skName = sortKeyName {
                LabeledContent {
                    TextField("", text: $sortKeyValue, prompt: Text("Enter value"))
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditing)
                } label: {
                    HStack(spacing: 6) {
                        Text(skName)
                        keyTypeBadge(sortKeyType ?? "S")
                    }
                }
            }
        }
    }

    private func keyTypeBadge(_ type: String) -> some View {
        Text(typeDisplayName(type))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
            .fixedSize()
    }

    // MARK: - Attributes Sections

    @ViewBuilder
    private var attributeSections: some View {
        ForEach($attributeRows) { $row in
            Section {
                TextField("Name", text: $row.name)
                Picker("Type", selection: $row.type) {
                    ForEach(AttributeValueType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .onChange(of: $row.wrappedValue.type) {
                    switch $row.wrappedValue.type {
                    case .bool:
                        if $row.wrappedValue.value != "true" && $row.wrappedValue.value != "false" {
                            $row.wrappedValue.value = "false"
                        }
                    case .null:
                        $row.wrappedValue.value = ""
                    case .list:
                        if $row.wrappedValue.value.isEmpty { $row.wrappedValue.value = "[]" }
                    case .map:
                        if $row.wrappedValue.value.isEmpty { $row.wrappedValue.value = "{}" }
                    default:
                        break
                    }
                }
                if $row.wrappedValue.type != .null {
                    attributeValueField(for: $row)
                }
            } header: {
                HStack {
                    Text("Attribute")
                    Spacer()
                    Button {
                        attributeRows.removeAll { $0.id == $row.wrappedValue.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        Section {
            Button {
                attributeRows.append(AttributeRow(name: "", value: "", type: .string))
            } label: {
                Label("Add Attribute", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func attributeValueField(for row: Binding<AttributeRow>) -> some View {
        switch row.wrappedValue.type {
        case .string, .number:
            TextField("Value", text: row.value)
                .font(.body.monospaced())
        case .stringSet:
            TextField("Value", text: row.value, prompt: Text("Comma-separated values"))
                .font(.body.monospaced())
        case .numberSet:
            TextField("Value", text: row.value, prompt: Text("Comma-separated numbers"))
                .font(.body.monospaced())
        case .bool:
            Picker("Value", selection: row.value) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
        case .null:
            EmptyView()
        case .list, .map:
            LabeledContent("Value") {
                TextEditor(text: row.value)
                    .font(.body.monospaced())
                    .frame(minHeight: 60, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
        }
    }

    // MARK: - Validation

    private var validationError: String? {
        if partitionKeyValue.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Partition key value is required."
        }
        if sortKeyName != nil && sortKeyValue.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Sort key value is required."
        }
        let names = attributeRows.map { $0.name.trimmingCharacters(in: .whitespaces) }
        let nonEmpty = names.filter { !$0.isEmpty }
        if Set(nonEmpty).count != nonEmpty.count {
            return "Attribute names must be unique."
        }
        for row in attributeRows where row.type == .number {
            let val = row.value.trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && Double(val) == nil {
                return "Invalid number for attribute \"\(row.name)\"."
            }
        }
        return nil
    }

    private var isValid: Bool {
        guard validationError == nil else { return false }
        guard !partitionKeyValue.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if sortKeyName != nil {
            guard !sortKeyValue.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }
        return true
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                var item: [String: AttributeValue] = [:]

                // Primary key
                item[partitionKeyName] = makeKeyValue(partitionKeyValue, type: partitionKeyType)
                if let skName = sortKeyName, let skType = sortKeyType {
                    item[skName] = makeKeyValue(sortKeyValue, type: skType)
                }

                // Attributes
                for row in attributeRows {
                    let name = row.name.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { continue }
                    if let av = buildAttributeValue(row) {
                        item[name] = av
                    }
                }

                try await service.putItem(tableName: tableDetail.tableName, item: item)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }

    private func makeKeyValue(_ value: String, type: String) -> AttributeValue {
        switch type {
        case "N": return .number(value)
        case "B": return .binary(value)
        default: return .string(value)
        }
    }

    private func buildAttributeValue(_ row: AttributeRow) -> AttributeValue? {
        let val = row.value.trimmingCharacters(in: .whitespaces)
        switch row.type {
        case .string: return .string(val)
        case .number: return .number(val)
        case .bool: return .bool(val == "true")
        case .null: return .null
        case .list:
            if let data = val.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return .list(arr.compactMap { parseAnyToAttributeValue($0) })
            }
            return .string(val) // fallback
        case .map:
            if let data = val.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var result: [String: AttributeValue] = [:]
                for (k, v) in dict {
                    if let av = parseAnyToAttributeValue(v) { result[k] = av }
                }
                return .map(result)
            }
            return .string(val) // fallback
        case .stringSet:
            let items = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return .stringSet(items)
        case .numberSet:
            let items = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return .numberSet(items)
        }
    }

    private func parseAnyToAttributeValue(_ value: Any) -> AttributeValue? {
        if let s = value as? String { return .string(s) }
        if let n = value as? NSNumber {
            if n === kCFBooleanTrue || n === kCFBooleanFalse {
                return .bool(n.boolValue)
            }
            return .number(n.stringValue)
        }
        if value is NSNull { return .null }
        if let arr = value as? [Any] {
            return .list(arr.compactMap { parseAnyToAttributeValue($0) })
        }
        if let dict = value as? [String: Any] {
            // Check if it's DynamoDB typed JSON
            if let av = AttributeValue.fromJSON(dict) { return av }
            // Otherwise treat as a plain map
            var result: [String: AttributeValue] = [:]
            for (k, v) in dict {
                if let av = parseAnyToAttributeValue(v) { result[k] = av }
            }
            return .map(result)
        }
        return nil
    }

    /// Decompose an AttributeValue back into (type enum, string representation) for the form
    static func decomposeAttributeValue(_ value: AttributeValue) -> (AttributeValueType, String) {
        switch value {
        case .string(let s): return (.string, s)
        case .number(let n): return (.number, n)
        case .binary(let b): return (.string, b)
        case .bool(let b): return (.bool, b ? "true" : "false")
        case .null: return (.null, "")
        case .list:
            let json = value.toJSON()
            if let data = try? JSONSerialization.data(withJSONObject: json["L"] as Any, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                return (.list, str)
            }
            return (.list, "[]")
        case .map:
            let json = value.toJSON()
            if let data = try? JSONSerialization.data(withJSONObject: json["M"] as Any, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return (.map, str)
            }
            return (.map, "{}")
        case .stringSet(let set): return (.stringSet, set.joined(separator: ", "))
        case .numberSet(let set): return (.numberSet, set.joined(separator: ", "))
        case .binarySet(let set): return (.stringSet, set.joined(separator: ", "))
        }
    }
}
