import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct S3ObjectBrowserView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    let bucket: S3Bucket

    @State private var objects: [S3Object] = []
    @State private var prefixes: [S3Prefix] = []
    @State private var pathComponents: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedObject: S3Object?
    @State private var showMetadata = false
    @State private var showPolicyEditor = false
    @State private var objectToDelete: S3Object?
    @State private var viewMode: S3BrowserViewMode = .list
    @State private var lastLoadTime: Date?

    private var currentPrefix: String {
        pathComponents.isEmpty ? "" : pathComponents.joined(separator: "/") + "/"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if viewMode != .column {
                breadcrumbBar
                Divider()
            }
            contentArea
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    viewModePicker

                    Button { loadObjects() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button { showPolicyEditor = true } label: {
                        Image(systemName: "doc.text")
                    }
                    .help("Bucket Policy")

                    if !appState.isReadOnly {
                        Button { uploadFile() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("Upload File")
                    }
                }
            }
        }
        .sheet(isPresented: $showMetadata) {
            if let obj = selectedObject {
                S3ObjectMetadataView(service: service, bucket: bucket.name, objectKey: obj.key)
            }
        }
        .sheet(isPresented: $showPolicyEditor) {
            S3BucketPolicyView(service: service, bucket: bucket.name)
        }
        .confirmationDialog(
            "Delete Object",
            isPresented: Binding(
                get: { objectToDelete != nil },
                set: { if !$0 { objectToDelete = nil } }
            ),
            presenting: objectToDelete
        ) { obj in
            Button("Delete \"\(obj.displayName)\"", role: .destructive) {
                deleteObject(obj)
            }
        } message: { obj in
            Text("Are you sure you want to delete \"\(obj.displayName)\"?")
        }
        .task(id: bucket.id) {
            pathComponents = []
            loadObjects()
        }
    }

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(S3BrowserViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewMode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .help(mode.label)
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(bucket.name) {
                    pathComponents = []
                    loadObjects()
                }
                .buttonStyle(.plain)
                .fontWeight(.medium)

                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(component) {
                        pathComponents = Array(pathComponents.prefix(index + 1))
                        loadObjects()
                    }
                    .buttonStyle(.plain)
                    .fontWeight(index == pathComponents.count - 1 ? .medium : .regular)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && objects.isEmpty && prefixes.isEmpty {
            ProgressView("Loading objects...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadObjects() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if objects.isEmpty && prefixes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewMode {
            case .list:
                listView
            case .icon:
                S3IconBrowserView(
                    items: rowItems,
                    onNavigate: { navigateToPrefix($0) },
                    onDownload: { downloadObject(key: $0) },
                    onShowMetadata: { key in
                        selectedObject = objects.first { $0.key == key }
                        showMetadata = true
                    },
                    onDelete: { key in
                        objectToDelete = objects.first { $0.key == key }
                    },
                    isReadOnly: appState.isReadOnly
                )
            case .column:
                S3ColumnBrowserView(
                    service: service,
                    bucket: bucket.name,
                    onDownload: { downloadObject(key: $0) },
                    onShowMetadata: { key in
                        selectedObject = objects.first { $0.key == key }
                        showMetadata = true
                    },
                    onDelete: { key in
                        objectToDelete = objects.first { $0.key == key }
                    },
                    isReadOnly: appState.isReadOnly
                )
            }
        }
    }

    private var listView: some View {
        Table(of: RowItem.self) {
            TableColumn("Name") { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .foregroundStyle(.secondary)
                    Text(item.name)
                }
            }
            TableColumn("Kind") { item in
                Text(item.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Size", value: \.size)
                .width(min: 60, ideal: 80)
            TableColumn("Date Added", value: \.lastModified)
                .width(min: 120, ideal: 160)
            TableColumn("Actions") { item in
                actionsForRow(item)
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(rowItems) { item in
                TableRow(item)
            }
        }
    }

    @ViewBuilder
    private func actionsForRow(_ item: RowItem) -> some View {
        if item.isFolder {
            Button { navigateToPrefix(item.fullKey) } label: {
                Image(systemName: "arrow.right")
            }
            .buttonStyle(.borderless)
        } else {
            HStack(spacing: 8) {
                Button { downloadObject(key: item.fullKey) } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Download")

                Button {
                    selectedObject = objects.first { $0.key == item.fullKey }
                    showMetadata = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Metadata")

                if !appState.isReadOnly {
                    Button(role: .destructive) {
                        objectToDelete = objects.first { $0.key == item.fullKey }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
        }
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

    private var rowItems: [RowItem] {
        let folderRows = prefixes.map { prefix in
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
        let objectRows = objects.map { obj in
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

    // MARK: - Actions

    private func navigateToPrefix(_ prefix: String) {
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        pathComponents = trimmed.components(separatedBy: "/")
        loadObjects()
    }

    private func loadObjects(force: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.listObjects(bucket: bucket.name, prefix: currentPrefix)
                objects = result.objects
                prefixes = result.commonPrefixes
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            lastLoadTime = Date()
        }
    }

    private func downloadObject(key: String) {
        Task {
            do {
                let data = try await service.getObject(bucket: bucket.name, key: key)
                let filename = key.components(separatedBy: "/").last ?? key
                let panel = NSSavePanel()
                panel.nameFieldStringValue = filename
                panel.canCreateDirectories = true
                let response = panel.runModal()
                if response == .OK, let url = panel.url {
                    try data.write(to: url)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        Task {
            do {
                let data = try Data(contentsOf: url)
                let filename = url.lastPathComponent
                let key = currentPrefix + filename
                let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                try await service.putObject(bucket: bucket.name, key: key, data: data, contentType: contentType)
                loadObjects()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteObject(_ obj: S3Object) {
        Task {
            do {
                try await service.deleteObject(bucket: bucket.name, key: obj.key)
                loadObjects()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
