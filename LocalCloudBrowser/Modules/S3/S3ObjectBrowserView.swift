import SwiftUI
import AppKit
import Quartz
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
    @EnvironmentObject private var transferManager: TransferManager
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
    @State private var isDropTargeted = false
    @State private var selectedRowIDs: Set<RowItem.ID> = []
    @State private var tableFocusTrigger: Int = 0
    @State private var serviceError: ServiceError?
    @State private var retryAction: (() -> Void)?
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

    // Single file download
    @State private var fileDownloadProgress: (downloaded: Int64, total: Int64?)?

    // Folder download
    @State private var folderDownloadProgress: (current: Int, total: Int)?
    @State private var emptyFolderAlert = false

    // Folder upload

    // Memoized row pipeline — recomputed only when objects/prefixes/sort/search/path change.
    // Accessing a computed property here would re-run the full filter+sort on every
    // view body evaluation, including every selection change — which tanked selection
    // responsiveness before this cache was introduced.
    @State private var sortedRows: [RowItem] = []
    @State private var totalItemCount: Int = 0
    @State private var filteredItemCount: Int = 0
    // ID-indexed lookups so user actions on N selected rows (delete, copy,
    // context menu) don't do O(N * sortedRows.count) linear scans. Rebuilt
    // together with sortedRows inside recomputeSortedRows(). On a 200-row
    // select-all + delete, this turns an 80,000-comparison pause before the
    // confirm alert into a handful of dictionary reads.
    @State private var rowsByID: [String: RowItem] = [:]
    @State private var objectsByKey: [String: S3Object] = [:]

    // Cancellable long-running task (move, delete folders, download zip, drop upload)
    @State private var longRunningTask: Task<Void, Never>?

    // Copy/paste
    @State private var isPasting = false

    // Collision warning
    @State private var collisionItems: [String] = []
    @State private var collisionAction: (() -> Void)?

    // Session restore
    @State private var hasRestoredPath = false

    // (Table focus is managed via `tableFocusTrigger` — AppKit NSTableView cannot
    // bind to @FocusState, so we bump the trigger and updateNSView makes the
    // table first responder on the next run loop tick.)

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
    /// Region this bucket lives in. Starts nil (use appState default). If a
    /// PermanentRedirect comes back pointing to a different region, we cache
    /// it here and pass as regionOverride on subsequent S3 calls for this
    /// bucket. Intentionally NOT mutating appState.region so other services
    /// (SQS, IAM, etc.) keep using the user's selected region.
    @State private var bucketRegion: String?
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
            || transferManager.hasActiveTransfersForBucket(bucket.name)
    }

    var body: some View {
        mainContent
            .serviceErrorAlert(error: $serviceError, retryAction: $retryAction)
            .focusedSceneValue(\.s3CopyAction, s3CopyAction)
            .focusedSceneValue(\.s3PasteAction, s3PasteAction)
            .focusedSceneValue(\.s3DeleteAction, s3DeleteAction)
            .focusedSceneValue(\.s3RefreshAction) { loadObjects(force: true) }
            .task(id: bucket.id) {
                // Per-file incremental refresh: append each finished upload to
                // the local list immediately instead of waiting for the whole
                // batch. Makes uploads feel alive — the user sees new rows
                // appear as each file completes.
                let thisBucket = bucket.name
                transferManager.onFileUploaded = { uploadBucket, key, size in
                    guard uploadBucket == thisBucket else { return }
                    appendUploadedObject(key: key, size: size, prefix: currentPrefix)
                }
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
                recomputeSortedRows()
            }
            // Memoization triggers — recompute sortedRows only on data changes,
            // not on every view body evaluation (e.g. selection change).
            .onChange(of: objects) { recomputeSortedRows() }
            .onChange(of: prefixes) { recomputeSortedRows() }
            .onChange(of: sortOrder) { recomputeSortedRows() }
            .onChange(of: searchQuery) { recomputeSortedRows() }
            .onChange(of: allPageObjects) { recomputeSortedRows() }
            .onChange(of: allPagePrefixes) { recomputeSortedRows() }
            // Sync toolbar display state
            .onChange(of: isLoading) { toolbarState.isLoading = isLoading }
            .onChange(of: isDeletingObjects) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: isDeletingFolders) { toolbarState.isDeleting = isDeletingObjects || isDeletingFolders }
            .onChange(of: selectedRowIDs) {
                toolbarState.hasSelection = !selectedRowIDs.subtracting([Self.parentRowID]).isEmpty
                followSelectionWithQuickLook()
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
                case .refresh: loadObjects(force: true)
                case .deleteSelected: deleteSelectedItems()
                }
            }
            // Spacebar → Quick Look
            .onKeyPress(.space) { handleSpacebarPreview() }
            // Arrow keys + Cmd+[/] → folder navigation
            .onKeyPress(phases: .down) { press in
                handleNavigationKeyPress(press)
            }
            .modifier(QuickLookAlertsModifier(
                quickLookSizeAlert: $quickLookSizeAlert,
                quickLookHardCapAlert: $quickLookHardCapAlert,
                quickLookDownloadError: Binding(
                    get: { quickLook.downloadError },
                    set: { quickLook.downloadError = $0 }
                ),
                emptyFolderAlert: $emptyFolderAlert,
                previewSizeLimitMB: appState.previewSizeLimitMB,
                onForcePreview: { key in forcePreview(key: key) }
            ))
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()
            contentArea
        }
        .onDisappear {
            longRunningTask?.cancel()
            transferManager.onFileUploaded = nil
        }
        .onChange(of: appState.s3Domain) {
            if errorMessage != nil {
                loadObjects(force: true)
            }
        }
        .onChange(of: paneFocusTrigger) {
            tableFocusTrigger &+= 1
            let selectable = sortedRows.filter { $0.id != Self.parentRowID }
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
                    if let progress = quickLook.downloadProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text("\(Int(progress * 100))%")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
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
        .deleteConfirmation(items: $objectsToDelete, noun: "Object") { items in
            if items.count == 1, let obj = items.first {
                Text("Are you sure you want to delete \"\(obj.displayName)\"?")
            } else {
                let names = items.map(\.displayName).joined(separator: "\n")
                Text("Are you sure you want to delete these items?\n\n\(names)")
            }
        } onDelete: { deleteObjects($0) }
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
        let allDeletable: [RowItem] = selectedRowIDs.compactMap { id in
            guard id != Self.parentRowID else { return nil }
            return rowsByID[id]
        }
        let folderPrefixes = allDeletable.filter { $0.isFolder }.map(\.fullKey)
        let fileObjs = allDeletable.filter { !$0.isFolder }.compactMap { objectsByKey[$0.fullKey] }
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
                if isSearchActive && sortedRows.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", message: "No matches for \"\(searchQuery)\"")
                } else if sortedRows.isEmpty || (sortedRows.count == 1 && sortedRows.first?.id == Self.parentRowID) {
                    EmptyStateView(
                        icon: currentPrefix.isEmpty ? "tray" : "folder",
                        message: currentPrefix.isEmpty ? "Empty bucket" : "Empty folder"
                    )
                        .contextMenu {
                            if !appState.isReadOnly {
                                Button("Create Folder") { showCreateFolder = true }
                                Divider()
                                Button("Upload File") { toolbarState.pendingAction = .uploadFile }
                                Button("Upload Folder") { toolbarState.pendingAction = .uploadFolder }
                                if let clip = appState.s3Clipboard, !clip.isEmpty {
                                    Divider()
                                    Button("Paste \(clip.totalCount) Item\(clip.totalCount == 1 ? "" : "s")") { performPaste() }
                                }
                            }
                        }
                } else {
                    listView
                }
                Divider()
                statusBar
            }
            .overlay {
                dropTargetOverlay
            }
            .overlay(alignment: .bottom) {
                transferPillOverlay
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

    // MARK: - Transfer Pill

    @ViewBuilder
    private var transferPillOverlay: some View {
        if transferManager.hasActiveTransfersForBucket(bucket.name) {
            let progress = transferManager.progressForBucket(bucket.name)
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(transferManager.summaryText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                Button {
                    transferManager.cancelForBucket(bucket.name)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .overlay {
                        Capsule()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
            }
            .padding(.bottom, 40)
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
            if isLoadingAllPages {
                return "Searching all pages..."
            }
            return "\(filteredItemCount) of \(totalItemCount) items"
        }
        return "\(totalItemCount) items"
    }

    private var selectionCount: Int {
        selectedRowIDs.subtracting([Self.parentRowID]).count
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                if isLoadingAllPages {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(statusBarText)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            if selectionCount > 1 {
                Text("(\(selectionCount) selected)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !isSearchActive && (isTruncated || currentPage > 1) {
                HStack(spacing: 8) {
                    Button {
                        loadPreviousPage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .disabled(currentPage <= 1 || isLoading)

                    Text("Page \(currentPage)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button {
                        loadNextPage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isTruncated || isLoading)
                }
            }

            Spacer()

            // Transfer queue progress
            if transferManager.hasActiveTransfersForBucket(bucket.name) {
                HStack(spacing: 6) {
                    ProgressView(value: transferManager.progressForBucket(bucket.name))
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text("\(Int(transferManager.progressForBucket(bucket.name) * 100))%")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = fileDownloadProgress {
                HStack(spacing: 6) {
                    if let total = progress.total, total > 0 {
                        ProgressView(value: Double(progress.downloaded), total: Double(total))
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                        Text("\(Int(Double(progress.downloaded) / Double(total) * 100))%")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let progress = folderDownloadProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Downloading folder... (\(progress.current)/\(progress.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var listView: some View {
        ObjectBrowserTableView(
            rows: sortedRows,
            selectedRowIDs: $selectedRowIDs,
            sortOrder: $sortOrder,
            isReadOnly: appState.isReadOnly,
            focusTrigger: tableFocusTrigger,
            onDoubleClick: { item in handleRowActivation(item) },
            onContextMenu: { ids in buildContextMenu(for: ids) },
            onSpacebar: { _ in _ = handleSpacebarPreview() },
            onDelete: { _ in
                guard !appState.isReadOnly,
                      !isDeletingObjects,
                      !isDeletingFolders,
                      !selectedRowIDs.subtracting([Self.parentRowID]).isEmpty else { return }
                deleteSelectedItems()
            },
            onActionButton: { item, action in handleRowActionButton(item, action) },
            onDragDownload: { item, url in
                try await service.downloadObjectToFile(
                    bucket: bucket.name,
                    key: item.fullKey,
                    destination: url
                )
            }
        )
    }

    private func handleRowActivation(_ item: RowItem) {
        if item.id == Self.parentRowID {
            navigateToParent()
        } else if item.isFolder {
            clearSearch()
            navigateToPrefix(item.fullKey)
        } else {
            selectedObject = objects.first { $0.key == item.fullKey }
        }
    }

    private func handleRowActionButton(_ item: RowItem, _ action: ObjectAction) {
        switch action {
        case .navigateParent:
            navigateToParent()
        case .openFolder:
            navigateToPrefix(item.fullKey)
        case .folderInfo:
            selectedFolderPrefix = item.fullKey
        case .download:
            downloadObject(key: item.fullKey)
        case .preview:
            requestPreview(key: item.fullKey)
        case .info:
            selectedObject = objects.first { $0.key == item.fullKey }
        case .delete:
            if item.isFolder {
                requestFolderDeletion(prefixes: [item.fullKey])
            } else {
                objectsToDelete = objects.filter { $0.key == item.fullKey }
            }
        }
    }

    // MARK: - Context Menu (NSMenu)

    private func buildContextMenu(for ids: Set<String>) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if ids.isEmpty {
            append(menu, title: "Create Folder", enabled: !appState.isReadOnly) {
                showCreateFolder = true
            }
            append(menu, title: "Upload File", enabled: !appState.isReadOnly) {
                uploadFile()
            }
            append(menu, title: "Upload Folder", enabled: !appState.isReadOnly) {
                toolbarState.pendingAction = .uploadFolder
            }
            menu.addItem(.separator())
            let pasteEnabled = !appState.isReadOnly && appState.s3Clipboard != nil && !isPasting
            append(menu, title: pasteLabel, enabled: pasteEnabled) {
                requestPaste()
            }
            return menu
        }

        let items = ids.compactMap { rowsByID[$0] }

        if items.count == 1, let item = items.first {
            buildSingleItemMenu(menu, item: item)
        } else {
            buildMultiSelectionMenu(menu, items: items)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func buildSingleItemMenu(_ menu: NSMenu, item: RowItem) {
        if item.id == Self.parentRowID {
            append(menu, title: "Go to Parent") { navigateToParent() }
            return
        }

        if item.isFolder {
            append(menu, title: "Open") { navigateToPrefix(item.fullKey) }
            append(menu, title: "Folder Info") { selectedFolderPrefix = item.fullKey }
            append(menu, title: "Open in New Window") {
                openWindow(value: S3BrowserTarget(bucket: bucket.name, prefix: item.fullKey))
            }
            append(menu, title: "Download as ZIP", enabled: folderDownloadProgress == nil) {
                downloadFolderAsZip(prefix: item.fullKey)
            }
            append(menu, title: "Copy") {
                copyItemsToClipboard(folderPrefixes: [item.fullKey])
            }
            menu.addItem(.separator())
            append(menu, title: "Copy Key") { copyToClipboard(item.fullKey) }
            append(menu, title: "Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
            append(menu, title: "Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
            menu.addItem(.separator())
            append(menu, title: "Rename", enabled: !appState.isReadOnly) {
                let folderName = String(item.fullKey.dropLast()).components(separatedBy: "/").last ?? item.fullKey
                renameText = folderName
                itemToRename = item
            }
            append(menu, title: "Move...", enabled: !appState.isReadOnly) {
                foldersToMove = [item.fullKey]
                moveDestination = currentPrefix
            }
            appendFolderMoveToMenu(menu, folders: [item.fullKey])
            append(menu, title: "Duplicate", enabled: !appState.isReadOnly) {
                duplicateItem(item)
            }
            menu.addItem(.separator())
            let pasteHereEnabled = !appState.isReadOnly && appState.s3Clipboard != nil && !isPasting
            append(menu, title: pasteHereLabel, enabled: pasteHereEnabled) {
                requestPaste(into: item.fullKey)
            }
            menu.addItem(.separator())
            appendDestructive(menu, title: "Delete Folder", enabled: !appState.isReadOnly) {
                requestFolderDeletion(prefixes: [item.fullKey])
            }
            return
        }

        // Single file
        append(menu, title: "Download") { downloadObject(key: item.fullKey) }
        append(menu, title: "Quick Look") { requestPreview(key: item.fullKey) }
        append(menu, title: "Copy") {
            copyItemsToClipboard(objectKeys: [item.fullKey])
        }
        append(menu, title: "Copy Key") { copyToClipboard(item.fullKey) }
        append(menu, title: "Copy S3 URI") { copyToClipboard(s3URI(for: item.fullKey)) }
        append(menu, title: "Copy as AWS JSON") { copyToClipboard(toAWSJSON([item.fullKey])) }
        menu.addItem(.separator())
        append(menu, title: "Metadata") {
            selectedObject = objects.first { $0.key == item.fullKey }
        }
        append(menu, title: "Rename", enabled: !appState.isReadOnly) {
            renameText = item.name
            itemToRename = item
        }
        append(menu, title: "Move...", enabled: !appState.isReadOnly) {
            if let obj = objects.first(where: { $0.key == item.fullKey }) {
                objectsToMove = [obj]
                moveDestination = currentPrefix
            }
        }
        if let obj = objects.first(where: { $0.key == item.fullKey }) {
            appendObjectMoveToMenu(menu, objects: [obj])
        }
        append(menu, title: "Duplicate", enabled: !appState.isReadOnly) {
            duplicateItem(item)
        }
        menu.addItem(.separator())
        appendDestructive(menu, title: "Delete", enabled: !appState.isReadOnly) {
            objectsToDelete = objects.filter { $0.key == item.fullKey }
        }
    }

    private func buildMultiSelectionMenu(_ menu: NSMenu, items: [RowItem]) {
        let selectedItems = items.filter { $0.id != Self.parentRowID }
        guard !selectedItems.isEmpty else { return }

        let folderItems = selectedItems.filter { $0.isFolder }
        let fileItems = selectedItems.filter { !$0.isFolder }

        let copyObjKeys = fileItems.map(\.fullKey)
        let copyFolderPrefixes = folderItems.map(\.fullKey)
        append(menu, title: "Copy \(selectedItems.count) \(selectedItems.count == 1 ? "Item" : "Items")") {
            copyItemsToClipboard(objectKeys: copyObjKeys, folderPrefixes: copyFolderPrefixes)
        }
        menu.addItem(.separator())

        if selectedItems.count > 1 {
            let keys = selectedItems.map(\.fullKey)
            let uris = keys.map { s3URI(for: $0) }
            append(menu, title: "Copy \(keys.count) Paths") { copyToClipboard(keys.joined(separator: "\n")) }
            append(menu, title: "Copy \(keys.count) S3 URIs") { copyToClipboard(uris.joined(separator: "\n")) }
            append(menu, title: "Copy as AWS JSON") { copyToClipboard(toAWSJSON(keys)) }
            menu.addItem(.separator())
        }

        let movableObjs = fileItems.compactMap { objectsByKey[$0.fullKey] }
        let movableFolders = folderItems.map(\.fullKey)
        let moveCount = movableObjs.count + movableFolders.count
        append(menu, title: "Move \(moveCount) Items...", enabled: !appState.isReadOnly) {
            objectsToMove = movableObjs
            foldersToMove = movableFolders
            moveDestination = currentPrefix
        }
        appendMixedMoveToMenu(menu, objects: movableObjs, folders: movableFolders)

        menu.addItem(.separator())
        let totalCount = selectedItems.count
        appendDestructive(menu, title: "Delete \(totalCount) Items", enabled: !appState.isReadOnly) {
            let fileObjs = fileItems.compactMap { objectsByKey[$0.fullKey] }
            if folderItems.isEmpty {
                objectsToDelete = fileObjs
            } else {
                standaloneObjectsToDelete = fileObjs
                requestFolderDeletion(prefixes: folderItems.map(\.fullKey))
            }
        }
    }

    // MARK: Move-to submenu builders

    private func appendFolderMoveToMenu(_ menu: NSMenu, folders: [String]) {
        let parent = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        parent.isEnabled = !appState.isReadOnly
        let submenu = NSMenu(title: "Move to")
        submenu.autoenablesItems = false

        let hasParent = !pathComponents.isEmpty
        let otherFolders = prefixes.filter { p in !folders.contains(p.prefix) }

        if hasParent {
            append(submenu, title: "..") {
                let parentPath = Array(pathComponents.dropLast())
                let dest = parentPath.isEmpty ? "" : parentPath.joined(separator: "/") + "/"
                foldersToMove = folders
                moveDestination = dest
                requestMove()
            }
            if !otherFolders.isEmpty { submenu.addItem(.separator()) }
        }
        for pfx in otherFolders {
            append(submenu, title: pfx.displayName) {
                foldersToMove = folders
                moveDestination = pfx.prefix
                requestMove()
            }
        }
        if !hasParent && otherFolders.isEmpty {
            let placeholder = NSMenuItem(title: "No folders", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        }
        submenu.addItem(.separator())
        append(submenu, title: "Browse...") {
            browsePickerItems = []
            browsePickerFolders = folders
            showBrowsePicker = true
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func appendObjectMoveToMenu(_ menu: NSMenu, objects objs: [S3Object]) {
        let parent = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        parent.isEnabled = !appState.isReadOnly
        let submenu = NSMenu(title: "Move to")
        submenu.autoenablesItems = false

        let hasParent = !pathComponents.isEmpty

        if hasParent {
            append(submenu, title: "..") {
                let parentPath = Array(pathComponents.dropLast())
                let dest = parentPath.isEmpty ? "" : parentPath.joined(separator: "/") + "/"
                objectsToMove = objs
                moveDestination = dest
                requestMove()
            }
            if !prefixes.isEmpty { submenu.addItem(.separator()) }
        }
        for pfx in prefixes {
            append(submenu, title: pfx.displayName) {
                objectsToMove = objs
                moveDestination = pfx.prefix
                requestMove()
            }
        }
        if !hasParent && prefixes.isEmpty {
            let placeholder = NSMenuItem(title: "No folders", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        }
        submenu.addItem(.separator())
        append(submenu, title: "Browse...") {
            browsePickerItems = objs
            browsePickerFolders = []
            showBrowsePicker = true
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func appendMixedMoveToMenu(_ menu: NSMenu, objects objs: [S3Object], folders: [String]) {
        let parent = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        parent.isEnabled = !appState.isReadOnly
        let submenu = NSMenu(title: "Move to")
        submenu.autoenablesItems = false

        let hasParent = !pathComponents.isEmpty
        let otherFolders = prefixes.filter { p in !folders.contains(p.prefix) }

        if hasParent {
            append(submenu, title: "..") {
                let parentPath = Array(pathComponents.dropLast())
                let dest = parentPath.isEmpty ? "" : parentPath.joined(separator: "/") + "/"
                objectsToMove = objs
                foldersToMove = folders
                moveDestination = dest
                requestMove()
            }
            if !otherFolders.isEmpty { submenu.addItem(.separator()) }
        }
        for pfx in otherFolders {
            append(submenu, title: pfx.displayName) {
                objectsToMove = objs
                foldersToMove = folders
                moveDestination = pfx.prefix
                requestMove()
            }
        }
        if !hasParent && otherFolders.isEmpty {
            let placeholder = NSMenuItem(title: "No folders", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            submenu.addItem(placeholder)
        }
        submenu.addItem(.separator())
        append(submenu, title: "Browse...") {
            browsePickerItems = objs
            browsePickerFolders = folders
            showBrowsePicker = true
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    // MARK: NSMenu helpers

    @discardableResult
    private func append(
        _ menu: NSMenu,
        title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = BlockMenuItem(title: title, handler: action)
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func appendDestructive(
        _ menu: NSMenu,
        title: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) {
        let item = BlockMenuItem(title: title, handler: action)
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        item.isEnabled = enabled
        menu.addItem(item)
    }

    fileprivate static let parentRowID = ".."

    private func recomputeSortedRows() {
        // Step 1: Build row items from current objects + prefixes.
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
        let allRows = folderRows + objectRows
        totalItemCount = allRows.count

        // Step 2: Apply search filter.
        let filtered: [RowItem]
        if isSearchActive {
            let query = searchQuery.lowercased()
            let isExtensionSearch = query.hasPrefix(".")
            filtered = allRows.filter { item in
                if isExtensionSearch {
                    return item.isFolder
                        ? item.name.lowercased().contains(query)
                        : item.name.lowercased().hasSuffix(query)
                }
                return item.name.lowercased().contains(query)
            }
        } else {
            filtered = allRows
        }
        filteredItemCount = filtered.count

        // Step 3: Sort, then prepend parent row when in a subfolder and not searching.
        let sorted = filtered.sorted(using: sortOrder)
        let finalRows: [RowItem]
        if !pathComponents.isEmpty && !isSearchActive {
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
            finalRows = [parentRow] + sorted
        } else {
            finalRows = sorted
        }
        sortedRows = finalRows

        // Step 4: Refresh ID indexes so per-action lookups are O(1).
        rowsByID = Dictionary(finalRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        objectsByKey = Dictionary((allPageObjects ?? objects).map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Per-row action buttons and context-menu "Move to" submenus are now built
    // in `ObjectBrowserTableView` / `build*ContextMenu*` on this view — see
    // `handleRowActionButton(_:_:)` and `appendObjectMoveToMenu(_:objects:)`.

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

    private var isSearchActive: Bool {
        !searchQuery.isEmpty
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
        // Queue drain: refresh object list when all uploads for this bucket complete
        .onChange(of: transferManager.lastBatchResult) {
            if case .completed(let batchBucket) = transferManager.lastBatchResult,
               batchBucket == bucket.name {
                loadObjects(force: true)
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

    private func handleNavigationKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .rightArrow where press.modifiers.isEmpty:
            guard let selected = singleSelectedItem, selected.isFolder, selected.id != Self.parentRowID else { return .ignored }
            navigateToPrefix(selected.fullKey)
            return .handled
        case .leftArrow where press.modifiers.isEmpty:
            guard !pathComponents.isEmpty else { return .ignored }
            navigateToParent()
            return .handled
        default:
            if press.characters == "[" && press.modifiers == .command {
                guard canGoBack else { return .ignored }
                navigateBack()
                return .handled
            }
            if press.characters == "]" && press.modifiers == .command {
                guard canGoForward else { return .ignored }
                navigateForward()
                return .handled
            }
            return .ignored
        }
    }

    /// Returns the single selected row item, or nil if zero or multiple rows are selected.
    private var singleSelectedItem: RowItem? {
        guard selectedRowIDs.count == 1, let id = selectedRowIDs.first else { return nil }
        return rowsByID[id]
    }

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
            tableFocusTrigger &+= 1
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
                    continuationToken: continuationToken,
                    regionOverride: bucketRegion
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
            } catch let error as CloudClientError {
                // Auto-redirect: if the bucket lives in a different region,
                // remember the region locally and retry with regionOverride.
                // Crucially, we do NOT mutate appState.region — that would
                // break other services (SQS, IAM, etc.) still using the
                // user's selected region.
                if let correctRegion = error.redirectRegion,
                   correctRegion != (bucketRegion ?? appState.region) {
                    Log.info("Bucket \(bucket.name) lives in \(correctRegion) — using per-bucket override", category: "S3")
                    bucketRegion = correctRegion
                    if !silent {
                        isLoading = false
                        lastLoadTime = nil
                    }
                    loadObjects(force: true, silent: silent)
                    return
                }
                if !silent {
                    errorMessage = error.localizedDescription
                    appState.autoRefresh.reportFailure()
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
        let filename = key.components(separatedBy: "/").last ?? key
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        fileDownloadProgress = (downloaded: 0, total: nil)
        Task {
            do {
                try await service.downloadObjectToFile(bucket: bucket.name, key: key, destination: url) { downloaded, total in
                    Task { @MainActor in
                        fileDownloadProgress = (downloaded: downloaded, total: total)
                    }
                }
                fileDownloadProgress = nil
            } catch {
                fileDownloadProgress = nil
                retryAction = { [self] in downloadObject(key: key) }
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
                let filename = url.lastPathComponent
                let key = currentPrefix + filename
                let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                try await service.uploadObject(bucket: bucket.name, key: key, fileURL: url, contentType: contentType)
                loadObjects(force: true)
            } catch {
                retryAction = { [self] in uploadFile() }
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
        var requests: [UploadRequest] = []
        for folderURL in folderURLs {
            let folderName = folderURL.lastPathComponent
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                let size = Int64(values?.fileSize ?? 0)
                let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
                let s3Key = currentPrefix + folderName + "/" + relativePath
                let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                requests.append(UploadRequest(
                    localURL: fileURL,
                    s3Key: s3Key,
                    bucket: bucket.name,
                    size: size,
                    contentType: contentType
                ))
            }
        }

        guard !requests.isEmpty else { return }

        let uploadService = service
        transferManager.enqueueUploads(requests) { request, _, progress in
            try await uploadService.uploadFile(
                bucket: request.bucket,
                key: request.s3Key,
                fileURL: request.localURL,
                contentType: request.contentType,
                progress: progress
            )
        }
    }

    @MainActor
    private func uploadFiles(from urls: [URL]) async {
        let requests: [UploadRequest] = urls.map { url in
            let fileSize = (try? Int64(url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)) ?? 0
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let key = currentPrefix + url.lastPathComponent
            return UploadRequest(
                localURL: url,
                s3Key: key,
                bucket: bucket.name,
                size: fileSize,
                contentType: contentType
            )
        }
        guard !requests.isEmpty else { return }

        let uploadService = service
        transferManager.enqueueUploads(requests) { request, _, progress in
            try await uploadService.uploadFile(
                bucket: request.bucket,
                key: request.s3Key,
                fileURL: request.localURL,
                contentType: request.contentType,
                progress: progress
            )
        }
    }

    /// Called on each file upload completion so the user sees rows appear as
    /// uploads finish, not only after the whole batch completes. Only mutates
    /// state when the user is still viewing the upload's prefix — switching
    /// folders mid-batch is a no-op for the out-of-view files.
    private func appendUploadedObject(key: String, size: Int64, prefix: String) {
        guard prefix == currentPrefix else { return }
        guard key.hasPrefix(prefix) else { return }

        let relativePath = String(key.dropFirst(prefix.count))

        if relativePath.contains("/") {
            // Folder upload — show the top-level folder prefix, not each file.
            let folderName = String(relativePath[..<relativePath.firstIndex(of: "/")!])
            let folderPrefix = prefix + folderName + "/"
            if !prefixes.contains(where: { $0.prefix == folderPrefix }) {
                prefixes.append(S3Prefix(prefix: folderPrefix))
            }
        } else {
            // Direct child — show the file itself.
            guard !key.hasSuffix("/") else { return }
            if !objects.contains(where: { $0.key == key }) {
                let obj = S3Object(key: key, size: size, lastModified: Date(), etag: "", storageClass: "STANDARD")
                objects.append(obj)
            }
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
                do {
                    for i in folderDeleteItems.indices {
                        guard !Task.isCancelled else { break }
                        let objs = try await service.listAllObjects(
                            bucket: bucket.name,
                            prefix: folderDeleteItems[i].prefix
                        )
                        folderDeleteItems[i].objectCount = objs.count
                        folderDeleteItems[i].totalSize = objs.reduce(0) { $0 + $1.size }
                        folderDeleteItems[i].allKeys = objs.map(\.key)
                    }
                } catch {
                    folderDeleteItems = []
                    serviceError = error.asServiceError
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
            selectedRowIDs.subtract(Set(objs.map(\.key)))
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
            let items = actionableIDs.compactMap { rowsByID[$0] }
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

    private func handleSpacebarPreview() -> KeyPress.Result {
        guard selectedRowIDs.count == 1,
              let id = selectedRowIDs.first,
              id != Self.parentRowID,
              let item = rowsByID[id],
              !item.isFolder else { return .ignored }
        requestPreview(key: item.fullKey)
        return .handled
    }

    // MARK: - Quick Look Preview

    /// When Quick Look is open and selection changes to a single file, preview it automatically (Finder behavior).
    private func followSelectionWithQuickLook() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        let real = selectedRowIDs.subtracting([Self.parentRowID])
        guard real.count == 1, let id = real.first else { return }
        guard let item = rowsByID[id], !item.isFolder else { return }
        requestPreview(key: item.fullKey)
    }

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

// MARK: - Quick Look Alerts Modifier

private struct QuickLookAlertsModifier: ViewModifier {
    @Binding var quickLookSizeAlert: QuickLookSizeAlert?
    @Binding var quickLookHardCapAlert: Bool
    @Binding var quickLookDownloadError: String?
    @Binding var emptyFolderAlert: Bool
    let previewSizeLimitMB: Int
    let onForcePreview: (String) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "File Too Large",
                isPresented: Binding(
                    get: { quickLookSizeAlert != nil },
                    set: { if !$0 { quickLookSizeAlert = nil } }
                )
            ) {
                if let alert = quickLookSizeAlert {
                    Button("Preview Anyway") { onForcePreview(alert.key) }
                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    Button("Cancel", role: .cancel) { quickLookSizeAlert = nil }
                }
            } message: {
                if let alert = quickLookSizeAlert {
                    Text("This file is \(alert.sizeMB) MB, which exceeds your preview limit of \(previewSizeLimitMB) MB. You can preview it anyway, or adjust the limit in Settings.")
                }
            }
            .alert("File Too Large", isPresented: $quickLookHardCapAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This file exceeds the 300 MB preview limit. Use Download to save it locally.")
            }
            .alert("Preview Failed", isPresented: Binding(
                get: { quickLookDownloadError != nil },
                set: { if !$0 { quickLookDownloadError = nil } }
            )) {
                Button("OK", role: .cancel) { quickLookDownloadError = nil }
            } message: {
                if let err = quickLookDownloadError {
                    Text(err)
                }
            }
            .alert("Empty Folder", isPresented: $emptyFolderAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This folder has no downloadable files.")
            }
    }
}

// MARK: - Context menu helper

/// NSMenuItem subclass that wires up a closure-based handler via target/action,
/// used for the SwiftUI-adjacent context menu in `ObjectBrowserTableView`.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    required init(coder: NSCoder) {
        fatalError("BlockMenuItem does not support NSCoder")
    }

    @objc private func invoke() {
        handler()
    }
}
