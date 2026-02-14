import SwiftUI

struct DynamoDBTableAttributesView: View {
    @ObservedObject var service: DynamoDBService
    let table: DynamoDBTable
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var detail: DynamoDBTableDetail?
    @State private var isLoading = false
    @State private var loadError: String?

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
                detailContent(detail)
            }

            Divider()

            bottomBar
        }
        .frame(width: 580)
        .frame(minHeight: 500)
        .task { loadDetail() }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if let detail {
                Button {
                    let cli = table.describeTableCLI(
                        endpointUrl: appState.endpoint,
                        region: appState.region
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cli, forType: .string)
                } label: {
                    Label("Copy as AWS CLI", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(detail.tableName.isEmpty)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(_ detail: DynamoDBTableDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection(detail)
                statsRow(detail)
                keySchemaSection(detail)
                attributesSection(detail)
                indexesSection(detail)
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private func headerSection(_ detail: DynamoDBTableDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(detail.tableName)
                    .font(.title3)
                    .fontWeight(.bold)
                statusBadge(detail.tableStatus)
            }
            if !detail.tableArn.isEmpty {
                CopyableValue(text: detail.tableArn)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                status == "ACTIVE" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(status == "ACTIVE" ? .green : .orange)
    }

    // MARK: - Stats Row

    private func statsRow(_ detail: DynamoDBTableDetail) -> some View {
        HStack(spacing: 10) {
            statCard(label: "Items", value: "\(detail.itemCount)")
            statCard(label: "Size", value: formatBytes(detail.tableSizeBytes))
            statCard(
                label: "Billing",
                value: detail.billingMode == "PAY_PER_REQUEST" ? "On-demand" : "Provisioned"
            )
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Key Schema

    private func keySchemaSection(_ detail: DynamoDBTableDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Schema")
                .font(.headline)

            if let pk = detail.partitionKey {
                keyRow(
                    role: "PK",
                    roleColor: .blue,
                    name: pk.attributeName,
                    type: detail.attributeType(for: pk.attributeName) ?? "S"
                )
            }
            if let sk = detail.sortKey {
                keyRow(
                    role: "SK",
                    roleColor: .purple,
                    name: sk.attributeName,
                    type: detail.attributeType(for: sk.attributeName) ?? "S"
                )
            }
        }
    }

    private func keyRow(role: String, roleColor: Color, name: String, type: String) -> some View {
        HStack(spacing: 8) {
            Text(role)
                .font(.caption2)
                .fontWeight(.bold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(roleColor.opacity(0.15), in: Capsule())
                .foregroundStyle(roleColor)

            Text(name)
                .fontWeight(.medium)

            typeBadge(type)
        }
    }

    // MARK: - Attribute Definitions

    private func attributesSection(_ detail: DynamoDBTableDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attributes")
                .font(.headline)

            WrappingHStack(spacing: 6) {
                ForEach(detail.attributeDefinitions) { attr in
                    attributePill(name: attr.attributeName, type: attr.attributeType)
                }
            }
        }
    }

    private func attributePill(name: String, type: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .fontWeight(.medium)
            Text(typeDisplayName(type))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor), in: Capsule())
    }

    // MARK: - Indexes

    @ViewBuilder
    private func indexesSection(_ detail: DynamoDBTableDetail) -> some View {
        let hasIndexes = !detail.globalSecondaryIndexes.isEmpty || !detail.localSecondaryIndexes.isEmpty
        if hasIndexes {
            VStack(alignment: .leading, spacing: 8) {
                Text("Indexes")
                    .font(.headline)

                ForEach(detail.globalSecondaryIndexes) { gsi in
                    indexCard(
                        name: gsi.indexName,
                        indexType: "GSI",
                        indexTypeColor: .orange,
                        projection: gsi.projection,
                        keySchema: gsi.keySchema,
                        detail: detail
                    )
                }
                ForEach(detail.localSecondaryIndexes) { lsi in
                    indexCard(
                        name: lsi.indexName,
                        indexType: "LSI",
                        indexTypeColor: .teal,
                        projection: lsi.projection,
                        keySchema: lsi.keySchema,
                        detail: detail
                    )
                }
            }
        }
    }

    private func indexCard(
        name: String,
        indexType: String,
        indexTypeColor: Color,
        projection: String,
        keySchema: [KeySchemaElement],
        detail: DynamoDBTableDetail
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(name)
                    .fontWeight(.medium)

                Text(indexType)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(indexTypeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(indexTypeColor)

                Spacer()

                Text(projection)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 12) {
                ForEach(keySchema) { key in
                    HStack(spacing: 4) {
                        Text(key.keyType == "HASH" ? "PK" : "SK")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(key.keyType == "HASH" ? .blue : .purple)
                        Text(key.attributeName)
                            .font(.caption)
                        typeBadge(detail.attributeType(for: key.attributeName) ?? "S")
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func typeBadge(_ type: String) -> some View {
        Text(typeDisplayName(type))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private func typeDisplayName(_ type: String) -> String {
        switch type {
        case "S": "String"
        case "N": "Number"
        case "B": "Binary"
        default: type
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
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

// MARK: - Wrapping HStack

/// A simple flow layout that wraps children to the next line when they exceed the available width.
private struct WrappingHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, offsets: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (CGSize(width: totalWidth, height: currentY + lineHeight), offsets)
    }
}
