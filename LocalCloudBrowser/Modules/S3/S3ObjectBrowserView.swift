import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Alert data for previewing files that exceed the user's size limit.
struct QuickLookSizeAlert: Identifiable {
    let id = UUID()
    let key: String
    let sizeMB: Int
}

struct S3ObjectBrowserView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let bucket: S3Bucket
    var paneID: String = "main"
    @ObservedObject var toolbarState: S3ToolbarState
    var restoreBucketName: String?
    var restorePath: [String]?
    var searchFocusTrigger: Int = 0
    var paneFocusTrigger: Int = 0

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
    @SceneStorage("S3ObjectColumns") private var columnCustomization: TableColumnCustomization<RowItem>
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
    @EnvironmentObject private var client: CloudClient

    // Quick Look preview
    @StateObject private var quickLook = S3QuickLookManager()
    @State private var quickLookSizeAlert: QuickLookSizeAlert?
    @State private var quickLookHardCapAlert = false

    // Rename
    @State private var itemToRename: RowItem?
    @State private var renameText = ""

    // Folder download
    @State private var folderDownloadProgress: (current: Int, total: Int)?
    @State private var emptyFolderAlert = false

    // Folder upload
    @State private var folderUploadProgress: (current: Int, total: Int)?
    @State private var folderUploadTask: Task<Void, Never>?

    // Cancellable long-running task (move, delete folders, download zip, drop upload)
    @State private var longRunningTask: Task<Void, Never>?

    // Copy/paste
    @State private var isPasting = false

    // Collision warning
    @State private var collisionItems: [String] = []
    @State private var collisionAction: (() -> Void)?

    // Session restore
    @State private var hasRestoredPath = false

    // Table focus
    @FocusState private var isTableFocused: Bool

    // Search & filter
    @State private var searchQuery = ""
    @State private var allPageObjects: [S3Object]?
    @State private var allPagePrefixes: [S3Prefix]?
    @State private var isLoadingAllPages = false

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
            || itemToRename != nil
            || folderDownloadProgress != nil
            || folderUploadProgress != nil
    }

    var body: some View {
        mainContent
            .serviceErrorAlert(error: $serviceError)
            .focusedSceneValue(\.s3CopyAction, s3CopyAction)
            .focusedSceneValue(\.s3PasteAction, s3PasteAction)
            .focusedSceneValue(\.s3DeleteAction, s3DeleteAction)
            .task(id: bucket.id) {
                var restoredPath: [String] = []
                if !hasRestoredPath,
                   let name = restoreBucketName, name == bucket.name,
                   let path = restorePath, !path.isEmpty {
                    restoredPath = path
                }
                hasRestoredPath = true
                pathComponents = restoredPath
                navigationHistory = [restoredPath]
                historyIndex = 0
                selectedRowIDs = []
                clearSearch()
                appState.autoRefresh.resetState()
                resetPagination()
                loadObjects(force: true)
            }
            .onAutoRefresh(canRefresh: { !anySheetOpen && !isLoading }) {
                loadObjects(force: true, silent: true)
            }
            .onChange(of: pathComponents) {
                LastSessionStore.saveS3Path(pathComponents)
            }
            // Sync toolbar display state
            .onChange(of: isLoading) { toolbarState.isLoading = isLoading }
            .onChange(of: isDeletingObjects) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: isDeletingFolders) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: selectedRowIDs) {
                toolbarState.hasSelection = !selectedRowIDs.subtracting([Self.parentRowID]).isEmpty
            }
            // Clear object selection when bucket list is clicked
            .onChange(of: toolbarState.clearSelectionTrigger) {
                selectedRowIDs = []
            }
            // Double-click bucket — navigate to root
            .onChange(of: toolbarState.resetToRootTrigger) {
                pathComponents = []
                navigationHistory = [[]]
                historyIndex = 0
                selectedRowIDs = []
                clearSearch()
                resetPagination()
                syncToolbarNavigation()
                loadObjects(force: true)
                refocusTable()
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
                case .uploadFile: uploadFile()
                case .uploadFolder: uploadFolder()
                case .deleteSelected: deleteSelectedItems()
                }
            }
            // Spacebar → Quick Look
            .onKeyPress(.space) {
                guard selectedRowIDs.count == 1,
                      let id = selectedRowIDs.first,
                      id != Self.parentRowID,
                      let item = sortedRowItems.first(where: { $0.id == id }),
                      !item.isFolder else { return .ignored }
                requestPreview(key: item.fullKey)
                return .handled
            }
            // Quick Look size limit alert (over user limit, under hard cap)
            .alert(
                "File Too Large",
                isPresented: Binding(
                    get: { quickLookSizeAlert != nil },
                    set: { if !$0 { quickLookSizeAlert = nil } }
                )
            ) {
                if let alert = quickLookSizeAlert {
                    Button("Preview Anyway") { forcePreview(key: alert.key) }
                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    Button("Cancel", role: .cancel) { quickLookSizeAlert = nil }
                }
            } message: {
                if let alert = quickLookSizeAlert {
                    Text("This file is \(alert.sizeMB) MB, which exceeds your preview limit of \(appState.previewSizeLimitMB) MB. You can preview it anyway, or adjust the limit in Settings.")
                }
            }
            // Quick Look hard cap alert (over 300 MB)
            .alert("File Too Large", isPresented: $quickLookHardCapAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This file exceeds the 300 MB preview limit. Use Download to save it locally.")
            }
            // Quick Look download error
            .alert("Preview Failed", isPresented: Binding(
                get: { quickLook.downloadError != nil },
                set: { if !$0 { quickLook.downloadError = nil } }
            )) {
                Button("OK", role: .cancel) { quickLook.downloadError = nil }
            } message: {
                if let err = quickLook.downloadError {
                    Text(err)
                }
            }
            // Empty folder download alert
            .alert("Empty Folder", isPresented: $emptyFolderAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This folder has no downloadable files.")
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            contentArea
        }
        .onDisappear {
            longRunningTask?.cancel()
            folderUploadTask?.cancel()
        }
        .onChange(of: appState.s3Domain) {
            if errorMessage != nil {
                loadObjects(force: true)
            }
        }
        .onChange(of: paneFocusTrigger) {
            isTableFocused = true
            let selectable = sortedRowItems.filter { $0.id != Self.parentRowID }
            if selectable.count == 1, let only = selectable.first {
                selectedRowIDs = [only.id]
            }
        }
        .onChange(of: searchQuery) {
            if !searchQuery.isEmpty {
                selectedRowIDs = []
                if isTruncated && allPageObjects == nil && !isLoadingAllPages {
                    fetchAllPages()
                }
            } else {
                allPageObjects = nil
                allPagePrefixes = nil
            }
        }
        .overlay {
            if quickLook.isDownloading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Downloading for preview...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
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
        .sheet(item: $itemToRename) { item in
            renameSheet(for: item)
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
        // Collision warning for move/paste
        .alert(
            "\(collisionItems.count) \(collisionItems.count == 1 ? "Item Already Exists" : "Items Already Exist")",
            isPresented: Binding(
                get: { !collisionItems.isEmpty },
                set: { if !$0 { collisionItems = []; collisionAction = nil } }
            )
        ) {
            Button("Stop", role: .cancel) {
                collisionItems = []
                collisionAction = nil
            }
            Button("Replace", role: .destructive) {
                let action = collisionAction
                collisionItems = []
                collisionAction = nil
                action?()
            }
        } message: {
            let names = collisionItems.joined(separator: "\n")
            Text("The destination already contains items with these names:\n\n\(names)\n\n• Matching items will be replaced\n• Other existing items will remain untouched\n• New items will be added")
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
                requestMove()
            } else {
                moveToBucketItems = browsePickerItems
                moveToBucketFolders = browsePickerFolders
                destinationBucketName = destBucket
                destinationBucketPrefix = destPrefix
                browsePickerItems = []
                browsePickerFolders = []
                requestMoveToBucket()
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
            }

            Spacer()

            SearchBarView(query: $searchQuery, placeholder: "Search in folder", focusTrigger: searchFocusTrigger)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && objects.isEmpty && prefixes.isEmpty {
            ProgressView("Loading objects...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            S3ConfigHintView(errorMessage: errorMessage, onRetry: { loadObjects() })
        } else {
            VStack(spacing: 0) {
                if isSearchActive && sortedRowItems.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", message: "No matches for \"\(searchQuery)\"")
                } else {
                    listView
                }
                Divider()
                statusBar
            }
            .overlay {
                dropTargetOverlay
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        }
    }

    // MARK: - Drop Target

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted && !appState.isReadOnly {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .background(Color.accentColor.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(4)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !appState.isReadOnly else { return false }
        let validProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !validProviders.isEmpty else { return false }
        longRunningTask?.cancel()
        longRunningTask = Task {
            var fileURLs: [URL] = []
            var folderURLs: [URL] = []
            for provider in validProviders {
                if let url: URL = await withCheckedContinuation({ continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }) {
                    if url.hasDirectoryPath {
                        folderURLs.append(url)
                    } else {
                        fileURLs.append(url)
                    }
                }
            }
            if !fileURLs.isEmpty {
                await uploadFiles(from: fileURLs)
            }
            if !folderURLs.isEmpty {
                uploadFolderURLs(from: folderURLs)
            }
        }
        return true
    }

    // MARK: - Status Bar

    private var statusBarText: String {
        if isSearchActive {
            let filtered = filteredRowItems.count
            let total = rowItems.count
            if isLoadingAllPages {
                return "Searching all pages..."
            }
            return "\(filtered) of \(total) items"
        }
        return "\(rowItems.count) items"
    }

    private var selectionCount: Int {
        selectedRowIDs.subtracting([Self.parentRowID]).count
    }

    private var statusBar: some View {
        HStack {
            HStack(spacing: 4) {
                if isLoadingAllPages {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(statusBarText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectionCount > 1 {
                Text("(\(selectionCount) selected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress = folderDownloadProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Downloading folder... (\(progress.current)/\(progress.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = folderUploadProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Uploading... (\(progress.current)/\(progress.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { folderUploadTask?.cancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !isSearchActive && (isTruncated || currentPage > 1) {
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
        Table(sortedRowItems, selection: $selectedRowIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .foregroundStyle(.secondary)
                    Text(item.name)
                }
            }
            .customizationID("name")
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
            .customizationID("kind")
            TableColumn("Size", value: \.sizeBytes) { item in
                Text(item.size)
            }
            .width(min: 60, ideal: 80)
            .customizationID("size")
            TableColumn("Date Modified", value: \.dateValue) { item in
                Text(item.lastModified)
            }
            .width(min: 100, ideal: 130)
            .customizationID("dateModified")
            TableColumn("Actions") { item in
                actionsForRow(item)
            }
            .width(min: 60, ideal: 80)
            .customizationID("actions")
        }
        .focused($isTableFocused)
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
                Divider()
                Button(pasteLabel) {
                    requestPaste()
                }
                .disabled(appState.isReadOnly || appState.s3Clipboard == nil || isPasting)
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
                    Button("Download as ZIP") {
                        downloadFolderAsZip(prefix: item.fullKey)
                    }
                    .disabled(folderDownloadProgress != nil)
                    Button("Copy") {
                        copyItemsToClipboard(folderPrefixes: [item.fullKey])
                    }
                    Divider()
                    Button("Copy Key") { copyToClipboard(item.fullKey) }
                    Button("Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
                    Button("Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
                    Divider()
                    Button("Rename") {
                        let folderName = String(item.fullKey.dropLast()).components(separatedBy: "/").last ?? item.fullKey
                        renameText = folderName
                        itemToRename = item
                    }
                    .disabled(appState.isReadOnly)
                    Button("Move...") {
                        foldersToMove = [item.fullKey]
                        moveDestination = currentPrefix
                    }
                    .disabled(appState.isReadOnly)
                    folderMoveToMenu(for: [item.fullKey])
                        .disabled(appState.isReadOnly)
                    Button("Duplicate") {
                        duplicateItem(item)
                    }
                    .disabled(appState.isReadOnly)
                    Divider()
                    Button(pasteHereLabel) {
                        requestPaste(into: item.fullKey)
                    }
                    .disabled(appState.isReadOnly || appState.s3Clipboard == nil || isPasting)
                    Divider()
                    Button(role: .destructive) {
                        requestFolderDeletion(prefixes: [item.fullKey])
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                    .disabled(appState.isReadOnly)
                } else {
                    Button("Download") { downloadObject(key: item.fullKey) }
                    Button("Quick Look") { requestPreview(key: item.fullKey) }
                    Button("Copy") {
                        copyItemsToClipboard(objectKeys: [item.fullKey])
                    }
                    Button("Copy Key") { copyToClipboard(item.fullKey) }
                    Button("Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
                    Button("Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
                    Divider()
                    Button("Metadata") {
                        selectedObject = objects.first { $0.key == item.fullKey }
                    }
                    Button("Rename") {
                        renameText = item.name
                        itemToRename = item
                    }
                    .disabled(appState.isReadOnly)
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
                    Button("Duplicate") {
                        duplicateItem(item)
                    }
                    .disabled(appState.isReadOnly)
                    Divider()
                    Button(role: .destructive) {
                        objectsToDelete = objects.filter { $0.key == item.fullKey }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                let selectedItems = items.filter { $0.id != Self.parentRowID }
                let folderItems = selectedItems.filter { $0.isFolder }
                let fileItems = selectedItems.filter { !$0.isFolder }

                if !selectedItems.isEmpty {
                    let copyObjKeys = fileItems.map(\.fullKey)
                    let copyFolderPrefixes = folderItems.map(\.fullKey)
                    Button("Copy \(selectedItems.count) \(selectedItems.count == 1 ? "Item" : "Items")") {
                        copyItemsToClipboard(objectKeys: copyObjKeys, folderPrefixes: copyFolderPrefixes)
                    }
                    Divider()
                }

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
                    Button(role: .destructive) {
                        let fileObjs = fileItems.compactMap { item in
                            objects.first { $0.key == item.fullKey }
                        }
                        if folderItems.isEmpty {
                            objectsToDelete = fileObjs
                        } else {
                            standaloneObjectsToDelete = fileObjs
                            requestFolderDeletion(prefixes: folderItems.map(\.fullKey))
                        }
                    } label: {
                        Label("Delete \(totalCount) Items", systemImage: "trash")
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

                Button { requestPreview(key: item.fullKey) } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .help("Quick Look")

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
                    requestMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(prefixes) { prefix in
                    Button(prefix.displayName) {
                        objectsToMove = objs
                        moveDestination = prefix.prefix
                        requestMove()
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
                    requestMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(otherFolders) { prefix in
                    Button(prefix.displayName) {
                        foldersToMove = folders
                        moveDestination = prefix.prefix
                        requestMove()
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
                    requestMove()
                }
                if hasFolders { Divider() }
            }
            if hasFolders {
                ForEach(otherFolders) { prefix in
                    Button(prefix.displayName) {
                        objectsToMove = objs
                        foldersToMove = folders
                        moveDestination = prefix.prefix
                        requestMove()
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
        let activePrefixes = allPagePrefixes ?? prefixes
        let activeObjects = allPageObjects ?? objects
        let folderRows = activePrefixes.map { prefix in
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
        let objectRows = activeObjects.filter { $0.key != currentPrefix }.map { obj in
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

    private var folderNameExists: Bool {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        let existingFolderNames = Set(prefixes.map(\.displayName))
        let existingFileNames = Set(objects.filter { $0.key != currentPrefix }.map(\.displayName))
        return existingFolderNames.contains(trimmed) || existingFileNames.contains(trimmed)
    }

    private var isValidFolderName: Bool {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        return !trimmed.isEmpty && !trimmed.hasPrefix("/") && !trimmed.hasSuffix("/")
            && !segments.contains("..")
            && !segments.contains(".")
            && !folderNameExists
    }

    private var createFolderSheet: some View {
        VStack(spacing: 16) {
            Text("Create Folder")
                .font(.headline)
            Text("in \(currentPrefix.isEmpty ? "/" : currentPrefix)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Folder name", text: $newFolderName)
                .onSubmit { if isValidFolderName { createFolder() } }
            if folderNameExists {
                Text("An item named \"\(newFolderName.trimmingCharacters(in: .whitespaces))\" already exists in this folder.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Rename Sheet

    private func renameSheet(for item: RowItem) -> some View {
        let isFolder = item.isFolder
        let currentName = isFolder
            ? String(item.fullKey.dropLast()).components(separatedBy: "/").last ?? item.fullKey
            : item.name
        let existingFileNames = Set(objects.filter { $0.key != currentPrefix }.map(\.displayName))
        let existingFolderNames = Set(prefixes.map(\.displayName))
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        let nameExists = isFolder
            ? existingFolderNames.contains(trimmed)
            : existingFileNames.contains(trimmed)
        let isValid: Bool = {
            if trimmed.isEmpty { return false }
            if trimmed == currentName { return false }
            if trimmed.contains("/") { return false }
            if nameExists { return false }
            return true
        }()

        return VStack(spacing: 16) {
            Text(isFolder ? "Rename Folder" : "Rename")
                .font(.headline)
            Text(currentName)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("New name", text: $renameText)
                .onSubmit { if isValid { performRename(item: item) } }
            if nameExists && trimmed != currentName {
                Text("An item named \"\(trimmed)\" already exists in this folder.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") {
                    itemToRename = nil
                    renameText = ""
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rename") { performRename(item: item) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func performRename(item: RowItem) {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        itemToRename = nil
        renameText = ""
        Task {
            do {
                if item.isFolder {
                    let newPrefix = currentPrefix + newName + "/"
                    try await service.renameFolder(bucket: bucket.name, sourcePrefix: item.fullKey, destinationPrefix: newPrefix)
                } else {
                    let newKey = currentPrefix + newName
                    try await service.renameObject(bucket: bucket.name, sourceKey: item.fullKey, destinationKey: newKey)
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
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
                    .onSubmit {
                        if !isMoveDisabled { requestMove() }
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
                    Button("Move") { requestMove() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isMoveDisabled)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    /// Returns the names of items that already exist at the destination.
    private func checkCollisions(
        bucket: String,
        destinationPrefix: String,
        incomingFileNames: [String],
        incomingFolderNames: [String]
    ) async -> [String] {
        do {
            let result = try await service.listObjects(bucket: bucket, prefix: destinationPrefix)
            let existingFileNames = Set(result.objects.filter { $0.key != destinationPrefix }.map(\.displayName))
            let existingFolderNames = Set(result.commonPrefixes.map(\.displayName))
            let allExisting = existingFileNames.union(existingFolderNames)
            let allIncoming = Set(incomingFileNames + incomingFolderNames)
            return Array(allIncoming.intersection(allExisting)).sorted()
        } catch {
            return []
        }
    }

    private func requestMove() {
        let objs = objectsToMove
        let folders = foldersToMove
        let destination = moveDestination

        let fileNames = objs.map { $0.key.components(separatedBy: "/").last ?? $0.key }
        let folderNames = folders.map { f in
            String(f.dropLast()).components(separatedBy: "/").last ?? f
        }

        Task {
            let collisions = await checkCollisions(
                bucket: bucket.name,
                destinationPrefix: destination,
                incomingFileNames: fileNames,
                incomingFolderNames: folderNames
            )
            if collisions.isEmpty {
                performMove()
            } else {
                collisionItems = collisions
                collisionAction = { performMove() }
            }
        }
    }

    private func requestMoveToBucket() {
        let objs = moveToBucketItems
        let folders = moveToBucketFolders
        let destBucket = destinationBucketName
        let destPrefix = destinationBucketPrefix

        let fileNames = objs.map { $0.key.components(separatedBy: "/").last ?? $0.key }
        let folderNames = folders.map { f in
            String(f.dropLast()).components(separatedBy: "/").last ?? f
        }

        Task {
            let collisions = await checkCollisions(
                bucket: destBucket,
                destinationPrefix: destPrefix,
                incomingFileNames: fileNames,
                incomingFolderNames: folderNames
            )
            if collisions.isEmpty {
                performMoveToBucket()
            } else {
                collisionItems = collisions
                collisionAction = { performMoveToBucket() }
            }
        }
    }

    private func requestPaste(into destinationPrefix: String? = nil) {
        guard let clipboard = appState.s3Clipboard else { return }
        let destPrefix = destinationPrefix ?? currentPrefix

        let fileNames = clipboard.objectKeys.map { $0.components(separatedBy: "/").last ?? $0 }
        let folderNames = clipboard.folderPrefixes.map { f in
            String(f.dropLast()).components(separatedBy: "/").last ?? f
        }

        Task {
            let collisions = await checkCollisions(
                bucket: bucket.name,
                destinationPrefix: destPrefix,
                incomingFileNames: fileNames,
                incomingFolderNames: folderNames
            )
            if collisions.isEmpty {
                performPaste(into: destinationPrefix)
            } else {
                collisionItems = collisions
                collisionAction = { performPaste(into: destinationPrefix) }
            }
        }
    }

    private func performMove() {
        let objs = objectsToMove
        let folders = foldersToMove
        let destination = moveDestination
        objectsToMove = []
        foldersToMove = []
        moveDestination = ""
        isMovingObjects = true
        longRunningTask?.cancel()
        longRunningTask = Task {
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
                    guard !Task.isCancelled else { break }
                    let folderName = String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                    let destPrefix = destination + folderName + "/"
                    try await service.moveFolder(bucket: bucket.name, sourcePrefix: folder, destinationPrefix: destPrefix)
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else if !Task.isCancelled {
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
                    Button("Move") { requestMoveToBucket() }
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
        longRunningTask?.cancel()
        longRunningTask = Task {
            do {
                for obj in objs {
                    guard !Task.isCancelled else { break }
                    let filename = obj.key.components(separatedBy: "/").last ?? obj.key
                    let destKey = destPrefix + filename
                    try await service.moveObjectToBucket(
                        sourceBucket: bucket.name, sourceKey: obj.key,
                        destinationBucket: destBucket, destinationKey: destKey
                    )
                }
                for folder in folders {
                    guard !Task.isCancelled else { break }
                    let folderName = String(folder.dropLast()).components(separatedBy: "/").last ?? folder
                    let destFolderPrefix = destPrefix + folderName + "/"
                    try await service.moveFolderToBucket(
                        sourceBucket: bucket.name, sourcePrefix: folder,
                        destinationBucket: destBucket, destinationPrefix: destFolderPrefix
                    )
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isMovingToBucket = false
        }
    }

    // MARK: - Search Helpers

    private func clearSearch() {
        searchQuery = ""
        allPageObjects = nil
        allPagePrefixes = nil
    }

    private func fetchAllPages() {
        isLoadingAllPages = true
        Task {
            do {
                let result = try await service.listAllFolderContents(bucket: bucket.name, prefix: currentPrefix)
                // Only apply if search is still active
                if isSearchActive {
                    allPageObjects = result.objects
                    allPagePrefixes = result.prefixes
                }
            } catch {
                // Silently fail — search falls back to current page data
            }
            isLoadingAllPages = false
        }
    }

    // MARK: - Navigation History

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func navigate(to components: [String]) {
        navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        navigationHistory.append(components)
        historyIndex += 1
        pathComponents = components
        selectedRowIDs = []
        resetPagination()
        syncToolbarNavigation()
        loadObjects(force: true)
        refocusTable()
    }

    private func navigateBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        pathComponents = navigationHistory[historyIndex]
        selectedRowIDs = []
        resetPagination()
        syncToolbarNavigation()
        loadObjects(force: true)
        refocusTable()
    }

    private func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        pathComponents = navigationHistory[historyIndex]
        selectedRowIDs = []
        resetPagination()
        refocusTable()
        syncToolbarNavigation()
        loadObjects(force: true)
    }

    private func syncToolbarNavigation() {
        toolbarState.canGoBack = canGoBack
        toolbarState.canGoForward = canGoForward
    }

    private func refocusTable() {
        DispatchQueue.main.async {
            isTableFocused = true
        }
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
        if !silent {
            isLoading = true
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
                if objects != result.objects {
                    objects = result.objects
                }
                if prefixes != result.commonPrefixes {
                    prefixes = result.commonPrefixes
                }
                errorMessage = nil
                if !silent {
                    appState.autoRefresh.reportSuccess()
                }
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
                    appState.autoRefresh.reportFailure()
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
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
                if let clientError = error as? CloudClientError,
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
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func uploadFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a folder to upload"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        uploadFolderURLs(from: [url])
    }

    private func uploadFolderURLs(from folderURLs: [URL]) {
        guard folderUploadProgress == nil else { return }

        // Enumerate all files from all folders
        var filesToUpload: [(localURL: URL, s3Key: String)] = []
        for folderURL in folderURLs {
            let folderName = folderURL.lastPathComponent
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true else { continue }
                let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
                let s3Key = currentPrefix + folderName + "/" + relativePath
                filesToUpload.append((localURL: fileURL, s3Key: s3Key))
            }
        }

        guard !filesToUpload.isEmpty else { return }

        folderUploadProgress = (current: 0, total: filesToUpload.count)
        folderUploadTask = Task {
            var failedCount = 0
            var lastError: ServiceError?

            for (index, file) in filesToUpload.enumerated() {
                if Task.isCancelled { break }
                do {
                    let data = try Data(contentsOf: file.localURL)
                    let contentType = UTType(filenameExtension: file.localURL.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                    try await service.putObject(bucket: bucket.name, key: file.s3Key, data: data, contentType: contentType)
                } catch {
                    failedCount += 1
                    if let clientError = error as? CloudClientError,
                       let parsed = clientError.serviceError {
                        lastError = parsed
                    } else {
                        lastError = ServiceError(code: "UploadError", message: error.localizedDescription)
                    }
                }
                folderUploadProgress = (current: index + 1, total: filesToUpload.count)
            }

            folderUploadProgress = nil
            folderUploadTask = nil
            loadObjects(force: true)
            if let lastError {
                serviceError = ServiceError(
                    code: lastError.code,
                    message: "\(failedCount) file\(failedCount == 1 ? "" : "s") failed to upload. Last error: \(lastError.message)"
                )
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
            if let clientError = error as? CloudClientError,
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
            longRunningTask?.cancel()
            longRunningTask = Task {
                for i in folderDeleteItems.indices {
                    guard !Task.isCancelled else { break }
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

        longRunningTask?.cancel()
        longRunningTask = Task {
            do {
                var allKeys: [String] = []

                for folder in folders {
                    guard !Task.isCancelled else { break }
                    if !folder.allKeys.isEmpty {
                        allKeys.append(contentsOf: folder.allKeys)
                    } else {
                        let objs = try await service.listAllObjects(bucket: bucket.name, prefix: folder.prefix)
                        allKeys.append(contentsOf: objs.map(\.key))
                    }
                }

                allKeys.append(contentsOf: standaloneFiles.map(\.key))

                if !allKeys.isEmpty && !Task.isCancelled {
                    _ = try await service.deleteObjects(bucket: bucket.name, keys: allKeys)
                }
                selectedRowIDs.subtract(Set(allKeys))
                selectedRowIDs.subtract(Set(folders.map(\.prefix)))
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else if !Task.isCancelled {
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
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isDeletingObjects = false
        }
    }

    // MARK: - Duplicate

    private func duplicateName(for name: String, existingNames: Set<String>) -> String {
        let stem: String
        let ext: String
        if let dotIndex = name.lastIndex(of: ".") {
            stem = String(name[name.startIndex..<dotIndex])
            ext = String(name[dotIndex...])
        } else {
            stem = name
            ext = ""
        }

        let candidate = "\(stem) copy\(ext)"
        if !existingNames.contains(candidate) { return candidate }

        for n in 2...99 {
            let numbered = "\(stem) copy \(n)\(ext)"
            if !existingNames.contains(numbered) { return numbered }
        }
        return "\(stem) copy\(ext)"
    }

    private func duplicateItem(_ item: RowItem) {
        Task {
            do {
                if item.isFolder {
                    let folderPrefix = item.fullKey
                    let folderName = String(folderPrefix.dropLast()).components(separatedBy: "/").last ?? folderPrefix
                    let existingNames = Set(prefixes.map(\.displayName))
                    let newName = duplicateName(for: folderName, existingNames: existingNames)
                    let newPrefix = currentPrefix + newName + "/"
                    try await service.duplicateFolder(bucket: bucket.name, sourcePrefix: folderPrefix, destinationPrefix: newPrefix)
                } else {
                    let filename = item.fullKey.components(separatedBy: "/").last ?? item.fullKey
                    let existingNames = Set(objects.filter { $0.key != currentPrefix }.map(\.displayName))
                    let newName = duplicateName(for: filename, existingNames: existingNames)
                    let newKey = currentPrefix + newName
                    try await service.duplicateObject(bucket: bucket.name, sourceKey: item.fullKey, destinationKey: newKey)
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Copy/Paste

    private var s3CopyAction: (() -> Void)? {
        let actionableIDs = selectedRowIDs.subtracting([Self.parentRowID])
        guard !actionableIDs.isEmpty else { return nil }
        return {
            let items = actionableIDs.compactMap { id in sortedRowItems.first(where: { $0.id == id }) }
            let fileKeys = items.filter { !$0.isFolder }.map(\.fullKey)
            let folderKeys = items.filter { $0.isFolder }.map(\.fullKey)
            copyItemsToClipboard(objectKeys: fileKeys, folderPrefixes: folderKeys)
        }
    }

    private var s3PasteAction: (() -> Void)? {
        guard appState.s3Clipboard != nil && !appState.isReadOnly && !isPasting else { return nil }
        return { requestPaste() }
    }

    private var s3DeleteAction: (() -> Void)? {
        let actionableIDs = selectedRowIDs.subtracting([Self.parentRowID])
        guard !actionableIDs.isEmpty && !appState.isReadOnly && !isDeletingObjects && !isDeletingFolders else { return nil }
        return { deleteSelectedItems() }
    }

    private func copyItemsToClipboard(objectKeys: [String] = [], folderPrefixes: [String] = []) {
        appState.s3Clipboard = S3Clipboard(
            sourceBucket: bucket.name,
            objectKeys: objectKeys,
            folderPrefixes: folderPrefixes
        )
    }

    private var pasteLabel: String {
        guard let clipboard = appState.s3Clipboard else { return "Paste" }
        return "Paste (\(clipboard.totalCount) \(clipboard.totalCount == 1 ? "Item" : "Items"))"
    }

    private var pasteHereLabel: String {
        guard let clipboard = appState.s3Clipboard else { return "Paste Here" }
        return "Paste Here (\(clipboard.totalCount) \(clipboard.totalCount == 1 ? "Item" : "Items"))"
    }

    private func performPaste(into destinationPrefix: String? = nil) {
        guard let clipboard = appState.s3Clipboard else { return }
        let destPrefix = destinationPrefix ?? currentPrefix
        isPasting = true
        Task {
            do {
                for key in clipboard.objectKeys {
                    let filename = key.components(separatedBy: "/").last ?? key
                    let destKey = destPrefix + filename
                    try await service.serverSideCopy(
                        sourceBucket: clipboard.sourceBucket, sourceKey: key,
                        destinationBucket: bucket.name, destinationKey: destKey)
                }
                for folderPrefix in clipboard.folderPrefixes {
                    let folderName = String(folderPrefix.dropLast())
                        .components(separatedBy: "/").last ?? folderPrefix
                    let destFolderPrefix = destPrefix + folderName + "/"
                    try await service.copyFolder(
                        sourceBucket: clipboard.sourceBucket, sourcePrefix: folderPrefix,
                        destinationBucket: bucket.name, destinationPrefix: destFolderPrefix)
                }
                loadObjects(force: true)
            } catch {
                if let clientError = error as? CloudClientError,
                   let svcError = clientError.serviceError {
                    serviceError = svcError
                }
            }
            isPasting = false
        }
    }

    // MARK: - Download Folder as ZIP

    private func downloadFolderAsZip(prefix: String) {
        guard folderDownloadProgress == nil else { return }
        folderDownloadProgress = (current: 0, total: 0)
        longRunningTask?.cancel()
        longRunningTask = Task {
            var tempDir: URL?
            do {
                let zipURL = try await service.downloadFolderAsZip(
                    bucket: bucket.name,
                    prefix: prefix
                ) { current, total in
                    Task { @MainActor in
                        folderDownloadProgress = (current: current, total: total)
                    }
                }
                folderDownloadProgress = nil

                guard let zipURL else {
                    emptyFolderAlert = true
                    return
                }
                tempDir = zipURL.deletingLastPathComponent()

                let folderName = String(prefix.dropLast()).components(separatedBy: "/").last ?? "folder"
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(folderName).zip"
                panel.canCreateDirectories = true
                let response = panel.runModal()
                if response == .OK, let dest = panel.url {
                    try FileManager.default.copyItem(at: zipURL, to: dest)
                }
                // Clean up temp
                if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
            } catch {
                folderDownloadProgress = nil
                if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
                if let clientError = error as? CloudClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Quick Look Preview

    private func requestPreview(key: String) {
        guard let obj = objects.first(where: { $0.key == key }) else { return }
        let sizeCheck = quickLook.checkSize(obj.size, limitBytes: appState.previewSizeLimitBytes)
        switch sizeCheck {
        case .allowed:
            Task { await quickLook.previewObject(bucket: bucket.name, key: key, using: client) }
        case .overLimit(let sizeMB):
            quickLookSizeAlert = QuickLookSizeAlert(key: key, sizeMB: sizeMB)
        case .overHardCap:
            quickLookHardCapAlert = true
        }
    }

    private func forcePreview(key: String) {
        Task { await quickLook.previewObject(bucket: bucket.name, key: key, using: client) }
    }
}
