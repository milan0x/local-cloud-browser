import SwiftUI

struct DynamoDBTableAttributesView: View {
    @ObservedObject var service: DynamoDBService
    let table: DynamoDBTable
    @Environment(\.dismiss) private var dismiss

    @State private var detail: DynamoDBTableDetail?
    @State private var isLoading = false
    @State private var loadError: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && detail == nil {
                ProgressView("Loading table details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadDetail() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                detailForm(detail)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 500)
        .task { loadDetail() }
    }

    @ViewBuilder
    private func detailForm(_ detail: DynamoDBTableDetail) -> some View {
        Form {
            Section("Table Info") {
                LabeledContent("Name") {
                    CopyableValue(text: detail.tableName)
                }
                LabeledContent("Status") {
                    Text(detail.tableStatus)
                        .foregroundStyle(detail.tableStatus == "ACTIVE" ? .green : .orange)
                }
                LabeledContent("Item Count") {
                    Text("\(detail.itemCount)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Size") {
                    Text(formatBytes(detail.tableSizeBytes))
                        .foregroundStyle(.secondary)
                }
                if let created = detail.creationDateTime {
                    LabeledContent("Created") {
                        CopyableValue(text: Self.dateFormatter.string(from: created))
                    }
                }
            }

            Section("Primary Key Schema") {
                if let pk = detail.partitionKey {
                    LabeledContent("Partition Key") {
                        HStack(spacing: 6) {
                            Text(pk.attributeName)
                                .fontWeight(.medium)
                            typeBadge(detail.attributeType(for: pk.attributeName) ?? "S")
                        }
                    }
                }
                if let sk = detail.sortKey {
                    LabeledContent("Sort Key") {
                        HStack(spacing: 6) {
                            Text(sk.attributeName)
                                .fontWeight(.medium)
                            typeBadge(detail.attributeType(for: sk.attributeName) ?? "S")
                        }
                    }
                }
            }

            Section("Attribute Definitions") {
                ForEach(detail.attributeDefinitions) { attr in
                    LabeledContent(attr.attributeName) {
                        typeBadge(attr.attributeType)
                    }
                }
            }

            if !detail.globalSecondaryIndexes.isEmpty {
                Section("Global Secondary Indexes") {
                    ForEach(detail.globalSecondaryIndexes) { gsi in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gsi.indexName)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                ForEach(gsi.keySchema) { key in
                                    HStack(spacing: 4) {
                                        Text(key.keyTypeDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(key.attributeName)
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Text(gsi.projection)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            if !detail.localSecondaryIndexes.isEmpty {
                Section("Local Secondary Indexes") {
                    ForEach(detail.localSecondaryIndexes) { lsi in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lsi.indexName)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                ForEach(lsi.keySchema) { key in
                                    HStack(spacing: 4) {
                                        Text(key.keyTypeDisplay)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(key.attributeName)
                                            .font(.caption)
                                    }
                                }
                                Spacer()
                                Text(lsi.projection)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Billing & Throughput") {
                LabeledContent("Billing Mode") {
                    Text(detail.billingMode == "PAY_PER_REQUEST" ? "Pay per request" : "Provisioned")
                        .foregroundStyle(.secondary)
                }
                if let pt = detail.provisionedThroughput, detail.billingMode != "PAY_PER_REQUEST" {
                    LabeledContent("Read Capacity") {
                        Text("\(pt.readCapacityUnits)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Write Capacity") {
                        Text("\(pt.writeCapacityUnits)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func typeBadge(_ type: String) -> some View {
        let display: String
        switch type {
        case "S": display = "String"
        case "N": display = "Number"
        case "B": display = "Binary"
        default: display = type
        }
        return Text(display)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) bytes" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func loadDetail() {
        isLoading = true
        loadError = nil
        Task {
            do {
                detail = try await service.describeTable(tableName: table.tableName)
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }
}
