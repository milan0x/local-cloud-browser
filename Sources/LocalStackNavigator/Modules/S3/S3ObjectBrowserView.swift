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
    @State private var showPolicyEditor = false
    @State private var objectToDelete: S3Object?
    @State private var lastLoadTime: Date?
    @State private var sortOrder: [KeyPathComparator<RowItem>] = [KeyPathComparator(\RowItem.name, order: .forward)]
    @State private var isDropTargeted = false
    @State private var selectedRowID: RowItem.ID?
    @State private var serviceError: ServiceError?

    // Pagination
    @State private var currentPage = 1
    @State private var continuationToken: String?
    @State private var nextPageToken: String?
    @State private var previousTokens: [String?] = []
    @State private var isTruncated = false
    @State private var totalItemsOnPage = 0

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
            breadcrumbBar
            Divider()
            contentArea
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button { loadObjects() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button { showPolicyEditor = true } label: {
                        Image(systemName: "doc.text")
                    }
                    .help("Bucket Policy")

                    Button { uploadFile() } label: {
                        Image(systemName: "plus")
                    }
                    .help("Upload File")
                    .disabled(appState.isReadOnly)
                }
            }
        }
        .sheet(item: $selectedObject) { obj in
            S3ObjectMetadataView(service: service, bucket: bucket.name, objectKey: obj.key)
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
        .serviceErrorAlert(error: $serviceError)
        .task(id: bucket.id) {
            pathComponents = []
            resetPagination()
            loadObjects()
        }
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
            VStack(spacing: 0) {
                listView
                Divider()
                statusBar
            }
            .overlay {
                if isDropTargeted && !appState.isReadOnly {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .background(Color.accentColor.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(4)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard !appState.isReadOnly else { return false }
                let validProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
                guard !validProviders.isEmpty else { return false }
                Task {
                    var urls: [URL] = []
                    for provider in validProviders {
                        if let url: URL = await withCheckedContinuation({ continuation in
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                continuation.resume(returning: url)
                            }
                        }) {
                            urls.append(url)
                        }
                    }
                    if !urls.isEmpty {
                        await uploadFiles(from: urls)
                    }
                }
                return true
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(totalItemsOnPage) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isTruncated || currentPage > 1 {
                Spacer()

                HStack(spacing: 12) {
                    Button {
                        loadPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage <= 1 || isLoading)

                    Text("Page \(currentPage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        loadNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isTruncated || isLoading)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var listView: some View {
        Table(sortedRowItems, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .foregroundStyle(.secondary)
                    Text(item.name)
                }
            }
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
            TableColumn("Size", value: \.sizeBytes) { item in
                Text(item.size)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Date Added", value: \.dateValue) { item in
                Text(item.lastModified)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Actions") { item in
                actionsForRow(item)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: RowItem.ID.self) { ids in
            if let id = ids.first, let item = sortedRowItems.first(where: { $0.id == id }) {
                if item.isFolder {
                    Button("Open") { navigateToPrefix(item.fullKey) }
                } else {
                    Button("Download") { downloadObject(key: item.fullKey) }
                    Button("Metadata") {
                        selectedObject = objects.first { $0.key == item.fullKey }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        objectToDelete = objects.first { $0.key == item.fullKey }
                    }
                    .disabled(appState.isReadOnly)
                }
            }
        } primaryAction: { ids in
            guard let id = ids.first, let item = sortedRowItems.first(where: { $0.id == id }) else { return }
            if item.isFolder {
                navigateToPrefix(item.fullKey)
            } else {
                selectedObject = objects.first { $0.key == item.fullKey }
            }
        }
    }

    private var sortedRowItems: [RowItem] {
        rowItems.sorted(using: sortOrder)
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
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Metadata")

                Button(role: .destructive) {
                    objectToDelete = objects.first { $0.key == item.fullKey }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(appState.isReadOnly ? .gray : .red)
                }
                .buttonStyle(.borderless)
                .help("Delete")
                .disabled(appState.isReadOnly)
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
        resetPagination()
        loadObjects()
    }

    private func resetPagination() {
        currentPage = 1
        continuationToken = nil
        previousTokens = []
        isTruncated = false
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
                let result = try await service.listObjects(
                    bucket: bucket.name,
                    prefix: currentPrefix,
                    continuationToken: continuationToken
                )
                objects = result.objects
                prefixes = result.commonPrefixes
                isTruncated = result.isTruncated
                totalItemsOnPage = result.keyCount
                // Store the next token for pagination
                if result.isTruncated {
                    nextPageToken = result.nextContinuationToken
                } else {
                    nextPageToken = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            lastLoadTime = Date()
        }
    }

    private func loadNextPage() {
        guard isTruncated, let nextPageToken else { return }
        previousTokens.append(continuationToken)
        continuationToken = nextPageToken
        currentPage += 1
        loadObjects(force: true)
    }

    private func loadPreviousPage() {
        guard currentPage > 1 else { return }
        continuationToken = previousTokens.removeLast()
        currentPage -= 1
        loadObjects(force: true)
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
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
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
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func uploadFiles(from urls: [URL]) async {
        do {
            for url in urls {
                let data = try Data(contentsOf: url)
                let key = currentPrefix + url.lastPathComponent
                let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                try await service.putObject(bucket: bucket.name, key: key, data: data, contentType: contentType)
            }
            loadObjects()
        } catch {
            if let clientError = error as? LocalStackClientError,
               let parsed = clientError.serviceError {
                serviceError = parsed
            } else {
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
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
