import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct S3ObjectBrowserView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let bucket: S3Bucket
    var paneID: String = "main"
    @ObservedObject var toolbarState: S3ToolbarState

    @State private var objects: [S3Object] = []
    @State private var prefixes: [S3Prefix] = []
    @State private var pathComponents: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedObject: S3Object?
    @State private var showPolicyEditor = false
    @State private var objectsToDelete: [S3Object] = []
    @State private var isDeletingObjects = false
    @State private var lastLoadTime: Date?
    @State private var sortOrder: [KeyPathComparator<RowItem>] = [KeyPathComparator(\RowItem.dateValue, order: .reverse)]
    @State private var isDropTargeted = false
    @State private var selectedRowIDs: Set<RowItem.ID> = []
    @State private var serviceError: ServiceError?
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var objectsToMove: [S3Object] = []
    @State private var foldersToMove: [String] = []
    @State private var isMovingObjects = false
    @State private var moveDestination = ""
    // Cross-bucket move
    @State private var showMoveToBucket = false
    @State private var moveToBucketItems: [S3Object] = []
    @State private var moveToBucketFolders: [String] = []
    @State private var destinationBucketName = ""
    @State private var destinationBucketPrefix = ""
    @State private var availableBuckets: [S3Bucket] = []
    @State private var isMovingToBucket = false
    // Browse folder picker
    @State private var showBrowsePicker = false
    @State private var browsePickerItems: [S3Object] = []
    @State private var browsePickerFolders: [String] = []
    // Folder info & deletion
    @State private var selectedFolderPrefix: String?
    @State private var folderDeleteItems: [FolderDeleteInfo] = []
    @State private var standaloneObjectsToDelete: [S3Object] = []
    @State private var isFetchingFolderDetails = false
    @State private var isDeletingFolders = false
    @AppStorage("showFolderDetailsOnDelete") private var showFolderDetailsOnDelete = false
    @EnvironmentObject private var autoRefresh: AutoRefreshManager

    // Search & filter
    @State private var searchQuery = ""

    // Navigation history
    @State private var navigationHistory: [[String]] = [[]]
    @State private var historyIndex: Int = 0

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

    private var anySheetOpen: Bool {
        showCreateFolder
            || selectedObject != nil
            || showPolicyEditor
            || !objectsToMove.isEmpty
            || !foldersToMove.isEmpty
            || showMoveToBucket
            || showBrowsePicker
            || !objectsToDelete.isEmpty
            || !folderDeleteItems.isEmpty
            || selectedFolderPrefix != nil
    }

    var body: some View {
        mainContent
            .serviceErrorAlert(error: $serviceError)
            .task(id: bucket.id) {
                pathComponents = []
                navigationHistory = [[]]
                historyIndex = 0
                clearSearch()
                autoRefresh.resetState()
                resetPagination()
                loadObjects(force: true)
            }
            .onChange(of: autoRefresh.refreshTrigger) {
                guard !anySheetOpen && !isLoading else { return }
                loadObjects(force: true, silent: true)
            }
            // Sync toolbar display state
            .onChange(of: isLoading) { toolbarState.isLoading = isLoading }
            .onChange(of: isDeletingObjects) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: isDeletingFolders) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: selectedRowIDs) {
                toolbarState.hasSelection = !selectedRowIDs.subtracting([Self.parentRowID]).isEmpty
            }
            // Handle toolbar actions
            .onChange(of: toolbarState.pendingAction) { _, action in
                guard let action else { return }
                toolbarState.pendingAction = nil
                switch action {
                case .navigateBack: navigateBack()
                case .navigateForward: navigateForward()
                case .showPolicy: showPolicyEditor = true
                case .createFolder: showCreateFolder = true
                case .upload: uploadFile()
                case .deleteSelected: deleteSelectedItems()
                }
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            contentArea
        }
        .sheet(item: $selectedObject) { obj in
            S3ObjectMetadataView(service: service, bucket: bucket.name, objectKey: obj.key)
        }
        .sheet(isPresented: Binding(
            get: { selectedFolderPrefix != nil },
            set: { if !$0 { selectedFolderPrefix = nil } }
        )) {
            if let prefix = selectedFolderPrefix {
                S3FolderMetadataView(service: service, bucket: bucket.name, prefix: prefix)
            }
        }
        .sheet(isPresented: $showPolicyEditor) {
            S3BucketPolicyView(service: service, bucket: bucket.name)
        }
        .sheet(isPresented: $showCreateFolder) {
            createFolderSheet
        }
        .sheet(isPresented: Binding(
            get: { !objectsToMove.isEmpty || !foldersToMove.isEmpty },
            set: { if !$0 { objectsToMove = []; foldersToMove = []; moveDestination = "" } }
        )) {
            moveSheet
        }
        .sheet(isPresented: $showMoveToBucket) {
            moveToBucketSheet
        }
        .sheet(isPresented: $showBrowsePicker) {
            browsePickerSheet
        }
        .alert(
            objectsToDelete.count == 1
                ? "Delete Object"
                : "Delete \(objectsToDelete.count) Objects",
            isPresented: Binding(
                get: { !objectsToDelete.isEmpty },
                set: { if !$0 { objectsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteObjects(objectsToDelete)
            }
            Button("Cancel", role: .cancel) {
                objectsToDelete = []
            }
        } message: {
            if objectsToDelete.count == 1, let obj = objectsToDelete.first {
                Text("Are you sure you want to delete \"\(obj.displayName)\"?")
            } else {
                let names = objectsToDelete.map(\.displayName).joined(separator: "\n")
                Text("Are you sure you want to delete these items?\n\n\(names)")
            }
        }
        .alert(
            folderDeleteItems.count + standaloneObjectsToDelete.count == 1
                ? "Delete Folder"
                : "Delete \(folderDeleteItems.count + standaloneObjectsToDelete.count) Items",
            isPresented: Binding(
                get: { !folderDeleteItems.isEmpty },
                set: { if !$0 {
                    folderDeleteItems = []
                    standaloneObjectsToDelete = []
                    isFetchingFolderDetails = false
                }}
            )
        ) {
            Button("Delete", role: .destructive) {
                executeFolderDelete()
            }
            Button("Cancel", role: .cancel) {
                folderDeleteItems = []
                standaloneObjectsToDelete = []
                isFetchingFolderDetails = false
            }
        } message: {
            let folderNames = folderDeleteItems.map { $0.displayName + "/" }
            let fileNames = standaloneObjectsToDelete.map(\.displayName)
            let allNames = (folderNames + fileNames).joined(separator: "\n")
            if folderDeleteItems.count + standaloneObjectsToDelete.count == 1 {
                Text("Are you sure you want to delete \"\(allNames)\"?\n\nAll contents will be permanently deleted.")
            } else {
                Text("Are you sure you want to delete these items?\n\n\(allNames)\n\nAll contents will be permanently deleted.")
            }
        }
    }

    private var browsePickerSheet: some View {
        S3FolderPickerView(
            service: service,
            currentBucket: bucket.name,
            currentPrefix: currentPrefix
        ) { destBucket, destPrefix in
            if destBucket == bucket.name {
                objectsToMove = browsePickerItems
                foldersToMove = browsePickerFolders
                moveDestination = destPrefix
                browsePickerItems = []
                browsePickerFolders = []
                performMove()
            } else {
                moveToBucketItems = browsePickerItems
                moveToBucketFolders = browsePickerFolders
                destinationBucketName = destBucket
                destinationBucketPrefix = destPrefix
                browsePickerItems = []
                browsePickerFolders = []
                performMoveToBucket()
            }
        }
    }

    private func deleteSelectedItems() {
        let allDeletable = allDeletableSelectedItems
        let folderPrefixes = allDeletable.filter { $0.isFolder }.map(\.fullKey)
        let fileObjs = allDeletable.filter { !$0.isFolder }.compactMap { item in
            objects.first { $0.key == item.fullKey }
        }
        if folderPrefixes.isEmpty {
            if !fileObjs.isEmpty { objectsToDelete = fileObjs }
        } else {
            standaloneObjectsToDelete = fileObjs
            requestFolderDeletion(prefixes: folderPrefixes)
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button(bucket.name) {
                        navigate(to: [])
                    }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)

                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(component) {
                            navigate(to: Array(pathComponents.prefix(index + 1)))
                        }
                        .buttonStyle(.plain)
                        .fontWeight(index == pathComponents.count - 1 ? .medium : .regular)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Spacer()

            SearchBarView(query: $searchQuery, placeholder: "Search in folder")
                .padding(.trailing, 8)
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
        } else if rowItems.isEmpty && !isSearchActive {
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Empty")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Folder") {
                    showCreateFolder = true
                }
                .disabled(appState.isReadOnly)
                Button("Upload File") {
                    uploadFile()
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if isSearchActive && sortedRowItems.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No matches for \"\(searchQuery)\"")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    listView
                }
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

    private var statusBarText: String {
        if isSearchActive {
            let filtered = filteredRowItems.count
            let total = rowItems.count
            return "\(filtered) of \(total) items"
        }
        return "\(rowItems.count) items"
    }

    private var statusBar: some View {
        HStack {
            Text(statusBarText)
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
        Table(sortedRowItems, selection: $selectedRowIDs, sortOrder: $sortOrder) {
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
            .width(min: 60, ideal: 90)
            TableColumn("Size", value: \.sizeBytes) { item in
                Text(item.size)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Date Added", value: \.dateValue) { item in
                Text(item.lastModified)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Actions") { item in
                actionsForRow(item)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: RowItem.ID.self) { ids in
            if ids.isEmpty {
                Button("Create Folder") {
                    showCreateFolder = true
                }
                .disabled(appState.isReadOnly)
                Button("Upload File") {
                    uploadFile()
                }
                .disabled(appState.isReadOnly)
            }
            let items = ids.compactMap { id in sortedRowItems.first(where: { $0.id == id }) }
            if items.count == 1, let item = items.first {
                if item.id == Self.parentRowID {
                    Button("Go to Parent") { navigateToParent() }
                } else if item.isFolder {
                    Button("Open") { navigateToPrefix(item.fullKey) }
                    Button("Folder Info") { selectedFolderPrefix = item.fullKey }
                    Button("Open in New Window") {
                        openWindow(value: S3BrowserTarget(bucket: bucket.name, prefix: item.fullKey))
                    }
                    Divider()
                    Button("Copy Key") { copyToClipboard(item.fullKey) }
                    Button("Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
                    Button("Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
                    Divider()
                    Button("Move...") {
                        foldersToMove = [item.fullKey]
                        moveDestination = currentPrefix
                    }
                    .disabled(appState.isReadOnly)
                    folderMoveToMenu(for: [item.fullKey])
                        .disabled(appState.isReadOnly)
                    Divider()
                    Button("Delete Folder", role: .destructive) {
                        requestFolderDeletion(prefixes: [item.fullKey])
                    }
                    .disabled(appState.isReadOnly)
                } else {
                    Button("Download") { downloadObject(key: item.fullKey) }
                    Button("Copy Key") { copyToClipboard(item.fullKey) }
                    Button("Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
                    Button("Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
                    Divider()
                    Button("Metadata") {
                        selectedObject = objects.first { $0.key == item.fullKey }
                    }
                    Button("Move...") {
                        if let obj = objects.first(where: { $0.key == item.fullKey }) {
                            objectsToMove = [obj]
                            moveDestination = currentPrefix
                        }
                    }
                    .disabled(appState.isReadOnly)
                    if let obj = objects.first(where: { $0.key == item.fullKey }) {
                        moveToMenu(for: [obj])
                            .disabled(appState.isReadOnly)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        objectsToDelete = objects.filter { $0.key == item.fullKey }
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                let selectedItems = items.filter { $0.id != Self.parentRowID }
                let folderItems = selectedItems.filter { $0.isFolder }
                let fileItems = selectedItems.filter { !$0.isFolder }

                if selectedItems.count > 1 {
                    let keys = selectedItems.map(\.fullKey)
                    let uris = keys.map { s3URI(for: $0) }
                    Button("Copy \(keys.count) Paths") { copyToClipboard(keys.joined(separator: "\n")) }
                    Button("Copy \(keys.count) S3 URIs") { copyToClipboard(uris.joined(separator: "\n")) }
                    Button("Copy as AWS JSON") { copyToClipboard(toAWSJSON(keys)) }
                    Divider()
                }

                if !selectedItems.isEmpty {
                    let movableObjs = fileItems.compactMap { item in
                        objects.first { $0.key == item.fullKey }
                    }
                    let movableFolders = folderItems.map(\.fullKey)
                    let moveCount = movableObjs.count + movableFolders.count
                    Button("Move \(moveCount) Items...") {
                        objectsToMove = movableObjs
                        foldersToMove = movableFolders
                        moveDestination = currentPrefix
                    }
                    .disabled(appState.isReadOnly)
                    mixedMoveToMenu(objects: movableObjs, folders: movableFolders)
                        .disabled(appState.isReadOnly)
                }

                if !selectedItems.isEmpty {
                    Divider()
                    let totalCount = selectedItems.count
                    Button("Delete \(totalCount) Items", role: .destructive) {
                        let fileObjs = fileItems.compactMap { item in
                            objects.first { $0.key == item.fullKey }
                        }
                        if folderItems.isEmpty {
                            objectsToDelete = fileObjs
                        } else {
                            standaloneObjectsToDelete = fileObjs
                            requestFolderDeletion(prefixes: folderItems.map(\.fullKey))
                        }
                    }
                    .disabled(appState.isReadOnly)
                }
            }
        } primaryAction: { ids in
            guard ids.count == 1,
                  let id = ids.first,
                  let item = sortedRowItems.first(where: { $0.id == id }) else { return }
            if item.id == Self.parentRowID {
                navigateToParent()
            } else if item.isFolder {
                clearSearch()
                navigateToPrefix(item.fullKey)
            } else {
                selectedObject = objects.first { $0.key == item.fullKey }
            }
        }
    }

    private static let parentRowID = ".."

    private var sortedRowItems: [RowItem] {
        let sorted = filteredRowItems.sorted(using: sortOrder)
        // Suppress parent row during active search
        guard !pathComponents.isEmpty && !isSearchActive else { return sorted }
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

    @ViewBuilder
    private func actionsForRow(_ item: RowItem) -> some View {
        if item.id == Self.parentRowID {
            Button { navigateToParent() } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
        } else if item.isFolder {
            HStack(spacing: 8) {
                Button { navigateToPrefix(item.fullKey) } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Open")

                Button { selectedFolderPrefix = item.fullKey } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Folder Info")

                Button(role: .destructive) {
                    requestFolderDeletion(prefixes: [item.fullKey])
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(appState.isReadOnly ? .gray : .red)
                }
                .buttonStyle(.borderless)
                .help("Delete Folder")
                .disabled(appState.isReadOnly)
            }
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
                    objectsToDelete = objects.filter { $0.key == item.fullKey }
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

    @ViewBuilder
    private func moveToMenu(for objs: [S3Object]) -> some View {
        let hasParent = !pathComponents.isEmpty
        let hasFolders = !prefixes.isEmpty
        Menu("Move to") {
            if hasParent {
                Button("..") {
                    let parent = Array(pathComponents.dropLast())
                    let dest = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
                    objectsToMove = objs
                    moveDestination = dest
                    performMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(prefixes) { prefix in
                    Button(prefix.displayName) {
                        objectsToMove = objs
                        moveDestination = prefix.prefix
                        performMove()
                    }
                }
            }
            if !hasParent && !hasFolders {
                Button("No folders") {}
                    .disabled(true)
            }
            Divider()
            Button("Browse...") {
                browsePickerItems = objs
                browsePickerFolders = []
                showBrowsePicker = true
            }
        }
    }

    @ViewBuilder
    private func folderMoveToMenu(for folders: [String]) -> some View {
        let hasParent = !pathComponents.isEmpty
        let otherFolders = prefixes.filter { p in !folders.contains(p.prefix) }
        let hasFolders = !otherFolders.isEmpty
        Menu("Move to") {
            if hasParent {
                Button("..") {
                    let parent = Array(pathComponents.dropLast())
                    let dest = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
                    foldersToMove = folders
                    moveDestination = dest
                    performMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(otherFolders) { prefix in
                    Button(prefix.displayName) {
                        foldersToMove = folders
                        moveDestination = prefix.prefix
                        performMove()
                    }
                }
            }
            if !hasParent && !hasFolders {
                Button("No folders") {}
                    .disabled(true)
            }
            Divider()
            Button("Browse...") {
                browsePickerItems = []
                browsePickerFolders = folders
                showBrowsePicker = true
            }
        }
    }

    @ViewBuilder
    private func mixedMoveToMenu(objects objs: [S3Object], folders: [String]) -> some View {
        let hasParent = !pathComponents.isEmpty
        let otherFolders = prefixes.filter { p in !folders.contains(p.prefix) }
        let hasFolders = !otherFolders.isEmpty
        Menu("Move to") {
            if hasParent {
                Button("..") {
                    let parent = Array(pathComponents.dropLast())
                    let dest = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
                    objectsToMove = objs
                    foldersToMove = folders
                    moveDestination = dest
                    performMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(otherFolders) { prefix in
                    Button(prefix.displayName) {
                        objectsToMove = objs
                        foldersToMove = folders
                        moveDestination = prefix.prefix
                        performMove()
                    }
                }
            }
            if !hasParent && !hasFolders {
                Button("No folders") {}
                    .disabled(true)
            }
            Divider()
            Button("Browse...") {
                browsePickerItems = objs
                browsePickerFolders = folders
                showBrowsePicker = true
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

    struct FolderDeleteInfo: Identifiable {
        let id: String
        let prefix: String
        let displayName: String
        var objectCount: Int?
        var totalSize: Int64?
        var allKeys: [String]
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
        let objectRows = objects.filter { $0.key != currentPrefix }.map { obj in
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

    private var isSearchActive: Bool {
        !searchQuery.isEmpty
    }

    private var filteredRowItems: [RowItem] {
        guard isSearchActive else { return rowItems }
        let query = searchQuery.lowercased()
        let isExtensionSearch = query.hasPrefix(".")
        return rowItems.filter { item in
            if isExtensionSearch {
                return item.isFolder
                    ? item.name.lowercased().contains(query)
                    : item.name.lowercased().hasSuffix(query)
            }
            return item.name.lowercased().contains(query)
        }
    }

    // MARK: - Create Folder Sheet

    private var isValidFolderName: Bool {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return !trimmed.isEmpty && !trimmed.hasPrefix("/") && !trimmed.hasSuffix("/")
            && !segments.contains("..")
            && !segments.contains(".")
    }

    private var createFolderSheet: some View {
        VStack(spacing: 16) {
            Text("Create Folder")
                .font(.headline)
            Text("in \(currentPrefix.isEmpty ? "/" : currentPrefix)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if isValidFolderName { createFolder() } }
            HStack {
                Button("Cancel") {
                    showCreateFolder = false
                    newFolderName = ""
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { createFolder() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValidFolderName)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        showCreateFolder = false
        newFolderName = ""
        Task {
            do {
                try await service.createFolder(bucket: bucket.name, prefix: currentPrefix, name: name)
                loadObjects(force: true)
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

    // MARK: - Move Sheet

    private var moveSheet: some View {
        let totalCount = objectsToMove.count + foldersToMove.count
        let isSingle = totalCount == 1
        let title: String = {
            if isSingle {
                return foldersToMove.isEmpty ? "Move Object" : "Move Folder"
            }
            return "Move \(totalCount) Items"
        }()
        let subtitle: String = {
            if isSingle {
                if let obj = objectsToMove.first {
                    return obj.key.components(separatedBy: "/").last ?? obj.key
                }
                if let folder = foldersToMove.first {
                    return String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                }
            }
            return "\(totalCount) items"
        }()
        let isMoveDisabled: Bool = {
            if moveDestination.isEmpty { return true }
            if moveDestination == currentPrefix { return true }
            return false
        }()

        return VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. folder/subfolder/", text: $moveDestination)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !isMoveDisabled { performMove() }
                    }
            }

            if !pathComponents.isEmpty {
                HStack(spacing: 8) {
                    Text("Quick:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Parent Folder") {
                        let parent = Array(pathComponents.dropLast())
                        moveDestination = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
            }

            let availablePrefixes = prefixes.filter { p in !foldersToMove.contains(p.prefix) }
            if !availablePrefixes.isEmpty {
                HStack(spacing: 8) {
                    Text("Subfolders:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(availablePrefixes.prefix(4)) { prefix in
                        Button(prefix.displayName) {
                            moveDestination = prefix.prefix
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
            }

            HStack {
                Button("Cancel") {
                    objectsToMove = []
                    foldersToMove = []
                    moveDestination = ""
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if isMovingObjects {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Move") { performMove() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isMoveDisabled)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func performMove() {
        let objs = objectsToMove
        let folders = foldersToMove
        let destination = moveDestination
        objectsToMove = []
        foldersToMove = []
        moveDestination = ""
        isMovingObjects = true
        Task {
            do {
                // Move files
                if !objs.isEmpty {
                    if objs.count == 1, let obj = objs.first {
                        let filename = obj.key.components(separatedBy: "/").last ?? obj.key
                        let destinationKey = destination + filename
                        try await service.moveObject(bucket: bucket.name, sourceKey: obj.key, destinationKey: destinationKey)
                    } else {
                        let keys = objs.map(\.key)
                        try await service.moveObjects(bucket: bucket.name, sourceKeys: keys, destinationPrefix: destination)
                    }
                }
                // Move folders
                for folder in folders {
                    let folderName = String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                    let destPrefix = destination + folderName + "/"
                    try await service.moveFolder(bucket: bucket.name, sourcePrefix: folder, destinationPrefix: destPrefix)
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isMovingObjects = false
        }
    }

    // MARK: - Move to Bucket Sheet

    private var moveToBucketSheet: some View {
        let totalCount = moveToBucketItems.count + moveToBucketFolders.count
        let isSingle = totalCount == 1
        let title: String = {
            if isSingle { return "Move to Bucket" }
            return "Move \(totalCount) Items to Bucket"
        }()
        let subtitle: String = {
            if isSingle {
                if let obj = moveToBucketItems.first {
                    return obj.key.components(separatedBy: "/").last ?? obj.key
                }
                if let folder = moveToBucketFolders.first {
                    return String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                }
            }
            return "\(totalCount) items"
        }()
        let filteredBuckets = availableBuckets.filter { $0.name != bucket.name }

        return VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination bucket")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if filteredBuckets.isEmpty {
                    Text("No other buckets available")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Picker("", selection: $destinationBucketName) {
                        Text("Select a bucket").tag("")
                        ForEach(filteredBuckets) { b in
                            Text(b.name).tag(b.name)
                        }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination prefix (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. folder/subfolder/", text: $destinationBucketPrefix)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    showMoveToBucket = false
                    moveToBucketItems = []
                    moveToBucketFolders = []
                    destinationBucketName = ""
                    destinationBucketPrefix = ""
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if isMovingToBucket {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Move") { performMoveToBucket() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(destinationBucketName.isEmpty)
                }
            }
        }
        .padding()
        .frame(width: 400)
        .task {
            do {
                availableBuckets = try await service.listBuckets()
            } catch {
                availableBuckets = []
            }
        }
    }

    private func performMoveToBucket() {
        let objs = moveToBucketItems
        let folders = moveToBucketFolders
        let destBucket = destinationBucketName
        let destPrefix = destinationBucketPrefix
        showMoveToBucket = false
        moveToBucketItems = []
        moveToBucketFolders = []
        destinationBucketName = ""
        destinationBucketPrefix = ""
        isMovingToBucket = true
        Task {
            do {
                for obj in objs {
                    let filename = obj.key.components(separatedBy: "/").last ?? obj.key
                    let destKey = destPrefix + filename
                    try await service.moveObjectToBucket(
                        sourceBucket: bucket.name, sourceKey: obj.key,
                        destinationBucket: destBucket, destinationKey: destKey
                    )
                }
                for folder in folders {
                    let folderName = String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                    let destFolderPrefix = destPrefix + folderName + "/"
                    try await service.moveFolderToBucket(
                        sourceBucket: bucket.name, sourcePrefix: folder,
                        destinationBucket: destBucket, destinationPrefix: destFolderPrefix
                    )
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isMovingToBucket = false
        }
    }

    // MARK: - Search Helpers

    private func clearSearch() {
        searchQuery = ""
    }

    // MARK: - Navigation History

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func navigate(to components: [String]) {
        navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        navigationHistory.append(components)
        historyIndex += 1
        pathComponents = components
        resetPagination()
        syncToolbarNavigation()
        loadObjects(force: true)
    }

    private func navigateBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        pathComponents = navigationHistory[historyIndex]
        resetPagination()
        syncToolbarNavigation()
        loadObjects(force: true)
    }

    private func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        pathComponents = navigationHistory[historyIndex]
        resetPagination()
        syncToolbarNavigation()
        loadObjects(force: true)
    }

    private func syncToolbarNavigation() {
        toolbarState.canGoBack = canGoBack
        toolbarState.canGoForward = canGoForward
    }

    // MARK: - Actions

    private func navigateToParent() {
        guard !pathComponents.isEmpty else { return }
        navigate(to: Array(pathComponents.dropLast()))
    }

    private func navigateToPrefix(_ prefix: String) {
        let trimmed = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let components = trimmed.components(separatedBy: "/")
        navigate(to: components)
    }

    private func resetPagination() {
        currentPage = 1
        continuationToken = nil
        previousTokens = []
        isTruncated = false
    }

    private func loadObjects(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        isLoading = true
        if !silent {
            errorMessage = nil
            objects = []
            prefixes = []
        }
        Task {
            do {
                let result = try await service.listObjects(
                    bucket: bucket.name,
                    prefix: currentPrefix,
                    continuationToken: continuationToken
                )
                objects = result.objects
                prefixes = result.commonPrefixes
                errorMessage = nil
                autoRefresh.reportSuccess()
                isTruncated = result.isTruncated
                totalItemsOnPage = result.keyCount
                // Store the next token for pagination
                if result.isTruncated {
                    nextPageToken = result.nextContinuationToken
                } else {
                    nextPageToken = nil
                }
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
                autoRefresh.reportFailure()
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
                loadObjects(force: true)
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
            loadObjects(force: true)
        } catch {
            if let clientError = error as? LocalStackClientError,
               let parsed = clientError.serviceError {
                serviceError = parsed
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var deletableSelectedObjects: [S3Object] {
        let deletableIDs = selectedRowIDs.filter { id in
            guard id != Self.parentRowID else { return false }
            guard let item = sortedRowItems.first(where: { $0.id == id }) else { return false }
            return !item.isFolder
        }
        return deletableIDs.compactMap { id in objects.first { $0.key == id } }
    }

    private var allDeletableSelectedItems: [RowItem] {
        selectedRowIDs.compactMap { id in
            guard id != Self.parentRowID else { return nil }
            return sortedRowItems.first(where: { $0.id == id })
        }
    }

    // MARK: - Folder Deletion


    private func requestFolderDeletion(prefixes: [String]) {
        folderDeleteItems = prefixes.map { prefix in
            let display = String(prefix.dropLast()).components(separatedBy: "/").last ?? prefix
            return FolderDeleteInfo(id: prefix, prefix: prefix, displayName: display, allKeys: [])
        }

        if showFolderDetailsOnDelete {
            isFetchingFolderDetails = true
            Task {
                for i in folderDeleteItems.indices {
                    let objs = try? await service.listAllObjects(
                        bucket: bucket.name,
                        prefix: folderDeleteItems[i].prefix
                    )
                    folderDeleteItems[i].objectCount = objs?.count ?? 0
                    folderDeleteItems[i].totalSize = objs?.reduce(0) { $0 + $1.size } ?? 0
                    folderDeleteItems[i].allKeys = objs?.map(\.key) ?? []
                }
                isFetchingFolderDetails = false
            }
        }
    }

    private func executeFolderDelete() {
        isDeletingFolders = true
        let folders = folderDeleteItems
        let standaloneFiles = standaloneObjectsToDelete
        folderDeleteItems = []
        standaloneObjectsToDelete = []

        Task {
            do {
                var allKeys: [String] = []

                for folder in folders {
                    if !folder.allKeys.isEmpty {
                        allKeys.append(contentsOf: folder.allKeys)
                    } else {
                        let objs = try await service.listAllObjects(bucket: bucket.name, prefix: folder.prefix)
                        allKeys.append(contentsOf: objs.map(\.key))
                    }
                }

                allKeys.append(contentsOf: standaloneFiles.map(\.key))

                if !allKeys.isEmpty {
                    _ = try await service.deleteObjects(bucket: bucket.name, keys: allKeys)
                }
                selectedRowIDs.subtract(Set(allKeys))
                selectedRowIDs.subtract(Set(folders.map(\.prefix)))
                loadObjects(force: true)
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isDeletingFolders = false
        }
    }

    private func toAWSJSON(_ keys: [String]) -> String {
        let objects = keys.map { ["Key": $0] }
        let payload: [String: Any] = ["Objects": objects]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func s3URI(for key: String) -> String {
        "s3://\(bucket.name)/\(key)"
    }

    private func deleteObjects(_ objs: [S3Object]) {
        guard !objs.isEmpty else { return }
        isDeletingObjects = true
        Task {
            do {
                let keys = objs.map(\.key)
                _ = try await service.deleteObjects(bucket: bucket.name, keys: keys)
                selectedRowIDs.subtract(Set(keys))
                loadObjects(force: true)
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isDeletingObjects = false
        }
    }
}
