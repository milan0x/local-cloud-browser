import SwiftUI
import AppKit

struct DynamoDBItemDetailView: View {
    let item: DynamoDBItem
    let tableDetail: DynamoDBTableDetail
    let tableName: String
    var onEdit: ((DynamoDBItem) -> Void)?
    var onDelete: ((DynamoDBItem) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private var keyAttributeNames: Set<String> {
        Set(tableDetail.keySchema.map(\.attributeName))
    }

    private var sortedNonKeyAttributes: [(key: String, value: AttributeValue)] {
        item.attributes
            .filter { !keyAttributeNames.contains($0.key) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Primary Key") {
                    if let pk = tableDetail.partitionKey {
                        LabeledContent(pk.attributeName) {
                            HStack(spacing: 6) {
                                CopyableValue(text: item.keyValue(for: pk.attributeName), monospaced: true)
                                attributeTypeBadge(tableDetail.attributeType(for: pk.attributeName) ?? "S")
                            }
                        }
                    }
                    if let sk = tableDetail.sortKey {
                        LabeledContent(sk.attributeName) {
                            HStack(spacing: 6) {
                                CopyableValue(text: item.keyValue(for: sk.attributeName), monospaced: true)
                                attributeTypeBadge(tableDetail.attributeType(for: sk.attributeName) ?? "S")
                            }
                        }
                    }
                }

                if !sortedNonKeyAttributes.isEmpty {
                    Section("Attributes (\(sortedNonKeyAttributes.count))") {
                        ForEach(sortedNonKeyAttributes, id: \.key) { key, value in
                            LabeledContent(key) {
                                HStack(spacing: 6) {
                                    attributeValueView(value)
                                    attributeTypeBadge(value.typeBadge)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Copy as JSON") {
                    copyToClipboard(item.toDisplayJSON())
                }

                Spacer()

                if !appState.isReadOnly {
                    Button("Edit") {
                        dismiss()
                        onEdit?(item)
                    }

                    Button("Delete", role: .destructive) {
                        dismiss()
                        onDelete?(item)
                    }
                }

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 400)
    }

    @ViewBuilder
    private func attributeValueView(_ value: AttributeValue) -> some View {
        switch value {
        case .string(let s):
            CopyableValue(text: s, monospaced: true)
        case .number(let n):
            CopyableValue(text: n, monospaced: true)
        case .binary(let b):
            CopyableValue(text: b, monospaced: true)
        case .bool(let b):
            Text(b ? "true" : "false")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        case .null:
            Text("null")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        case .map, .list:
            let jsonStr = prettyPrintValue(value)
            VStack(alignment: .trailing, spacing: 4) {
                CopyButton(text: jsonStr)
                Text(jsonStr)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        case .stringSet(let set), .numberSet(let set), .binarySet(let set):
            CopyableValue(text: set.joined(separator: ", "), monospaced: true)
        }
    }

    private func attributeTypeBadge(_ type: String) -> some View {
        Text(type)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeColor(type).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(type))
    }

    private func badgeColor(_ type: String) -> Color {
        switch type {
        case "S": .blue
        case "N": .green
        case "B": .orange
        case "BOOL": .purple
        case "NULL": .gray
        case "L": .orange
        case "M": .teal
        case "SS", "NS", "BS": .cyan
        default: .gray
        }
    }

    private func prettyPrintValue(_ value: AttributeValue) -> String {
        let json = value.toJSON()
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return value.displayString
        }
        return str
    }
}
