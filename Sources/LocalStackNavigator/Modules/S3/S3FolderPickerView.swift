import SwiftUI

struct S3FolderPickerView: View {
    let service: S3Service
    let currentBucket: String
    let currentPrefix: String
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedBucket: String
    @State private var browsePrefix = ""
    @State private var folders: [S3Prefix] = []
    @State private var objects: [S3Object] = []
    @State private var buckets: [S3Bucket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sortOrder: [KeyPathComparator<RowItem>] = [KeyPathComparator(\RowItem.dateValue, order: .reverse)]

    init(service: S3Service, currentBucket: String, currentPrefix: String, onSelect: @escaping (String, String) -> Void) {
        self.service = service
        self.currentBucket = currentBucket
        self.currentPrefix = currentPrefix
        self.onSelect = onSelect
        _selectedBucket = State(initialValue: currentBucket)
    }

    private var pathComponents: [String] {
        guard !browsePrefix.isEmpty else { return [] }
        let trimmed = browsePrefix.hasSuffix("/") ? String(browsePrefix.dropLast()) : browsePrefix
        return trimmed.components(separatedBy: "/")
    }

    // MARK: - Row Model

    struct RowItem: Identifiable {
        let id: String
        let name: String
        let fullKey: String
        let kind: String
        let size: String
        let sizeBytes: Int64
        let lastModified: String
        let dateValue: Date
        let isFolder: Bool
        let icon: String
    }

    private static let parentRowID = ".."

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var rowItems: [RowItem] {
        let folderRows = folders.map { prefix in
            RowItem(
                id: prefix.prefix,
                name: prefix.displayName,
                fullKey: prefix.prefix,
                kind: "Folder",
                size: "--",
                sizeBytes: -1,
                lastModified: "--",
                dateValue: .distantPast,
                isFolder: true,
                icon: S3FileKind.icon(for: prefix.displayName, isFolder: true)
            )
        }
        let objectRows = objects.filter { $0.key != browsePrefix }.map { obj in
            RowItem(
                id: obj.key,
                name: obj.displayName,
                fullKey: obj.key,
                kind: S3FileKind.kind(for: obj.displayName),
                size: obj.formattedSize,
                sizeBytes: obj.size,
                lastModified: obj.lastModified.map { Self.dateFormatter.string(from: $0) } ?? "--",
                dateValue: obj.lastModified ?? .distantPast,
                isFolder: false,
                icon: S3FileKind.icon(for: obj.displayName, isFolder: false)
            )
        }
        return folderRows + objectRows
    }

    private var sortedRowItems: [RowItem] {
        let sorted = rowItems.sorted(using: sortOrder)
        guard !pathComponents.isEmpty else { return sorted }
        let parentRow = RowItem(
            id: Self.parentRowID,
            name: "..",
            fullKey: Self.parentRowID,
            kind: "Parent Folder",
            size: "--",
            sizeBytes: -1,
            lastModified: "--",
            dateValue: .distantFuture,
            isFolder: true,
            icon: "arrow.up.doc"
        )
        return [parentRow] + sorted
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bucketPicker
            breadcrumbBar
            Divider()
            contentArea
            Divider()
            destinationBar
            Divider()
            buttons
        }
        .frame(width: 600)
        .task(id: selectedBucket + "|" + browsePrefix) {
            await loadContents()
        }
        .task {
            await loadBuckets()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Destination")
                    .font(.headline)
                Text("Select a bucket and folder to move into")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Bucket Picker

    private var bucketPicker: some View {
        HStack(spacing: 8) {
            Text("Bucket:")
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedBucket) {
                ForEach(buckets) { b in
                    Text(b.name).tag(b.name)
                }
            }
            .labelsHidden()
            .onChange(of: selectedBucket) {
                browsePrefix = ""
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(selectedBucket) {
                    browsePrefix = ""
                }
                .buttonStyle(.plain)
                .fontWeight(.medium)

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(component) {
                        browsePrefix = pathComponents.prefix(index + 1).joined(separator: "/") + "/"
                    }
                    .buttonStyle(.plain)
                    .fontWeight(index == pathComponents.count - 1 ? .medium : .regular)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && objects.isEmpty && folders.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
        } else if rowItems.isEmpty && pathComponents.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("You can still move items here")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                tableView
                Divider()
                statusBar
            }
        }
    }

    private var tableView: some View {
        Table(sortedRowItems, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .foregroundStyle(item.isFolder ? .secondary : .tertiary)
                    Text(item.name)
                        .foregroundStyle(item.isFolder ? .primary : .tertiary)
                }
            }
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind)
                    .foregroundStyle(item.isFolder ? .secondary : .tertiary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Size", value: \.sizeBytes) { item in
                Text(item.size)
                    .foregroundStyle(item.isFolder ? .primary : .tertiary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Date Added", value: \.dateValue) { item in
                Text(item.lastModified)
                    .foregroundStyle(item.isFolder ? .primary : .tertiary)
            }
            .width(min: 100, ideal: 130)
        }
        .contextMenu(forSelectionType: RowItem.ID.self) { _ in } primaryAction: { ids in
            guard ids.count == 1,
                  let id = ids.first,
                  let item = sortedRowItems.first(where: { $0.id == id }) else { return }
            if item.id == Self.parentRowID {
                let parent = Array(pathComponents.dropLast())
                browsePrefix = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
            } else if item.isFolder {
                browsePrefix = item.fullKey
            }
            // Ignore files — they're shown for context only
        }
        .frame(minHeight: 250)
    }

    private var statusBar: some View {
        HStack {
            Text("\(rowItems.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Destination Bar

    private var destinationBar: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 13))
                .padding(.trailing, 4)
            Button {
                browsePrefix = ""
            } label: {
                Text(selectedBucket)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.plain)
            Text("/")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.quaternary)
            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                Button {
                    browsePrefix = pathComponents.prefix(index + 1).joined(separator: "/") + "/"
                } label: {
                    Text(component)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if index < pathComponents.count - 1 {
                    Text("/")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                onSelect(selectedBucket, browsePrefix)
                dismiss()
            } label: {
                Label("Move Here", systemImage: "arrow.right")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Loading

    private func loadContents() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await service.listObjects(
                bucket: selectedBucket,
                prefix: browsePrefix
            )
            folders = result.commonPrefixes
            objects = result.objects
        } catch {
            errorMessage = "Failed to load contents"
            folders = []
            objects = []
        }
        isLoading = false
    }

    private func loadBuckets() async {
        do {
            buckets = try await service.listBuckets()
            if !buckets.contains(where: { $0.name == selectedBucket }) {
                if let first = buckets.first {
                    selectedBucket = first.name
                }
            }
        } catch {
            buckets = [S3Bucket(name: currentBucket, creationDate: nil)]
        }
    }
}
