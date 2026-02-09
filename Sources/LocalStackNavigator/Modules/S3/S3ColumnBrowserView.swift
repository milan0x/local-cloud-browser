import SwiftUI

struct S3ColumnBrowserView: View {
    @ObservedObject var service: S3Service
    let bucket: String
    let onDownload: (String) -> Void
    let onShowMetadata: (String) -> Void
    let onDelete: (String) -> Void
    let isReadOnly: Bool

    @State private var columns: [ColumnData] = [ColumnData(prefix: "", items: [])]
    @State private var selections: [String?] = [nil]
    @State private var isLoading = false

    struct ColumnData: Identifiable {
        let id = UUID()
        let prefix: String
        var items: [ColumnItem]
    }

    struct ColumnItem: Identifiable, Hashable {
        let id: String
        let name: String
        let fullKey: String
        let isFolder: Bool
        let icon: String
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    columnView(column, at: index)
                    if index < columns.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .task { await loadColumn(at: 0, prefix: "") }
    }

    private func columnView(_ column: ColumnData, at index: Int) -> some View {
        List(column.items, selection: Binding(
            get: { selections.indices.contains(index) ? selections[index] : nil },
            set: { newValue in
                // Update selection
                while selections.count <= index { selections.append(nil) }
                selections[index] = newValue

                // Trim columns after this one
                let keepCount = index + 1
                if columns.count > keepCount + 1 {
                    columns = Array(columns.prefix(keepCount + 1))
                    selections = Array(selections.prefix(keepCount + 1))
                }

                // If selected item is a folder, load next column
                if let key = newValue,
                   let item = column.items.first(where: { $0.id == key }),
                   item.isFolder {
                    Task { await loadColumn(at: index + 1, prefix: item.fullKey) }
                } else {
                    // Remove any column after this one
                    if columns.count > keepCount {
                        columns = Array(columns.prefix(keepCount))
                        selections = Array(selections.prefix(keepCount))
                    }
                }
            }
        )) { item in
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                if item.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contextMenu {
                if item.isFolder {
                    // No special actions for folders in column view
                } else {
                    Button("Download") { onDownload(item.fullKey) }
                    Button("Metadata") { onShowMetadata(item.fullKey) }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete(item.fullKey) }
                        .disabled(isReadOnly)
                }
            }
        }
        .listStyle(.plain)
        .frame(width: 220)
    }

    private func loadColumn(at index: Int, prefix: String) async {
        do {
            let result = try await service.listObjects(bucket: bucket, prefix: prefix)

            let folderItems = result.commonPrefixes.map { p in
                ColumnItem(
                    id: p.prefix,
                    name: p.displayName,
                    fullKey: p.prefix,
                    isFolder: true,
                    icon: S3FileKind.icon(for: p.displayName, isFolder: true)
                )
            }
            let fileItems = result.objects.map { obj in
                ColumnItem(
                    id: obj.key,
                    name: obj.displayName,
                    fullKey: obj.key,
                    isFolder: false,
                    icon: S3FileKind.icon(for: obj.displayName, isFolder: false)
                )
            }

            let newColumn = ColumnData(prefix: prefix, items: folderItems + fileItems)

            if index < columns.count {
                columns[index] = newColumn
                // Trim any columns beyond this one
                if columns.count > index + 1 {
                    columns = Array(columns.prefix(index + 1))
                    selections = Array(selections.prefix(index + 1))
                }
            } else {
                columns.append(newColumn)
                selections.append(nil)
            }
        } catch {
            // Silently handle — column stays empty
        }
    }
}
