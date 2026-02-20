import SwiftUI

struct S3FileBrowserView: View {
    let client: CloudClient
    let initialUri: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = S3Service()

    @State private var selectedBucket: String
    @State private var browsePrefix: String
    @State private var folders: [S3Prefix] = []
    @State private var objects: [S3Object] = []
    @State private var buckets: [S3Bucket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRowID: String?
    @State private var sortOrder: [KeyPathComparator<RowItem>] = [KeyPathComparator(\RowItem.dateValue, order: .reverse)]

    init(client: CloudClient, initialUri: String = "", onSelect: @escaping (String) -> Void) {
        self.client = client
        self.initialUri = initialUri
        self.onSelect = onSelect

        var bucket = ""
        var prefix = ""
        if initialUri.hasPrefix("s3://") {
            let path = String(initialUri.dropFirst(5))
            let parts = path.split(separator: "/", maxSplits: 1)
            if let first = parts.first {
                bucket = String(first)
                if parts.count > 1 {
                    let key = String(parts[1])
                    if let lastSlash = key.lastIndex(of: "/") {
                        prefix = String(key[...lastSlash])
                    }
                }
            }
        }
        _selectedBucket = State(initialValue: bucket)
        _browsePrefix = State(initialValue: prefix)
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

    private var selectedFile: RowItem? {
        guard let id = selectedRowID else { return nil }
        return sortedRowItems.first { $0.id == id && !$0.isFolder }
    }

    private var selectedS3Uri: String? {
        guard let file = selectedFile else { return nil }
        return "s3://\(selectedBucket)/\(file.fullKey)"
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
            selectionBar
            Divider()
            buttons
        }
        .frame(width: 600)
        .task {
            service.updateClient(client)
            await loadBuckets()
        }
        .task(id: selectedBucket + "|" + browsePrefix) {
            guard !selectedBucket.isEmpty else { return }
            await loadContents()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse S3")
                    .font(.headline)
                Text("Select a file from S3")
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
                selectedRowID = nil
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
                    selectedRowID = nil
                }
                .buttonStyle(.plain)
                .fontWeight(.medium)

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(component) {
                        browsePrefix = pathComponents.prefix(index + 1).joined(separator: "/") + "/"
                        selectedRowID = nil
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
            EmptyStateView(icon: "folder", message: "Empty Bucket")
                .frame(minHeight: 250)
        } else {
            VStack(spacing: 0) {
                tableView
                Divider()
                statusBar
            }
        }
    }

    private var tableView: some View {
        Table(sortedRowItems, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .foregroundStyle(item.isFolder ? .secondary : .tertiary)
                    Text(item.name)
                }
            }
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Size", value: \.sizeBytes) { item in
                Text(item.size)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Date Added", value: \.dateValue) { item in
                Text(item.lastModified)
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
                selectedRowID = nil
            } else if item.isFolder {
                browsePrefix = item.fullKey
                selectedRowID = nil
            } else {
                onSelect("s3://\(selectedBucket)/\(item.fullKey)")
                dismiss()
            }
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

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: 4) {
            if let uri = selectedS3Uri {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))
                Text(uri)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Image(systemName: "doc.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text("Select a file to continue")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                if let uri = selectedS3Uri {
                    onSelect(uri)
                    dismiss()
                }
            } label: {
                Label("Select", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedS3Uri == nil)
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
            if !selectedBucket.isEmpty && buckets.contains(where: { $0.name == selectedBucket }) {
                return
            }
            if let first = buckets.first {
                selectedBucket = first.name
            }
        } catch {
            errorMessage = "Failed to load buckets"
        }
    }
}
