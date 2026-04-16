import SwiftUI
import AppKit

struct S3BucketListView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedBucketIDs: Set<S3Bucket.ID>
    @Binding var activeBucket: S3Bucket?
    @ObservedObject var toolbarState: S3ToolbarState
    var restoreBucketName: String?
    var searchFocusTrigger: Int = 0
    var paneFocusTrigger: Int = 0

    @Environment(\.openWindow) private var openWindow
    @FocusState private var isListFocused: Bool
    @StateObject private var loader = ListLoader<S3Bucket>()
    private var buckets: [S3Bucket] { loader.items }
    @State private var showCreateSheet = false
    @State private var bucketsToDelete: [S3Bucket] = []
    @State private var serviceError: ServiceError?
    @State private var forceDeleteBuckets: [S3Bucket] = []
    @State private var forceDeleteConfirmation = ""
    @State private var isForceDeleting = false
    @State private var forceDeleteProgress = 0
    @State private var forceDeleteTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var pendingSelectName: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            bucketListHeader
            Divider()
            bucketListContent
                .overlay {
                    if isForceDeleting {
                        ZStack {
                            Color(nsColor: .windowBackgroundColor).opacity(0.8)
                            ProgressView(forceDeleteProgress > 0
                                ? "Deleting... (\(forceDeleteProgress) objects removed)"
                                : "Deleting...")
                        }
                    }
                }
        }
        .disabled(isForceDeleting)
        .background(PaneClickDetector {
            toolbarState.clearSelectionTrigger += 1
        })
        .sheet(isPresented: $showCreateSheet) {
            S3CreateBucketView(service: service, existingBucketNames: Set(loader.items.map(\.name))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadBuckets(force: true) }
        }
        .deleteConfirmation(items: $bucketsToDelete, noun: "Bucket") { items in
            if items.count == 1, let bucket = items.first {
                Text("Are you sure you want to delete \"\(bucket.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these buckets?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteBuckets($0) }
        .serviceErrorAlert(error: $serviceError)
        .sheet(isPresented: Binding(
            get: { !forceDeleteBuckets.isEmpty },
            set: { if !$0 { forceDeleteBuckets = []; forceDeleteConfirmation = "" } }
        )) {
            ForceDeleteSheet(
                buckets: forceDeleteBuckets,
                confirmation: $forceDeleteConfirmation,
                onConfirm: {
                    let targets = forceDeleteBuckets
                    forceDeleteBuckets = []
                    forceDeleteConfirmation = ""
                    performForceDelete(targets)
                },
                onCancel: {
                    forceDeleteBuckets = []
                    forceDeleteConfirmation = ""
                }
            )
        }
        .task { loadBuckets() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && bucketsToDelete.isEmpty && forceDeleteBuckets.isEmpty && !isForceDeleting && !loader.isLoading }) {
            loadBuckets(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedBucketIDs = []
            activeBucket = nil
            loader.items = []
            loadBuckets(force: true)
        }
        .onChange(of: appState.s3Domain) {
            if loader.errorMessage != nil {
                loadBuckets(force: true)
            }
        }
        .syncSelection(selectedBucketIDs, items: buckets, activeItem: $activeBucket)
        .onChange(of: paneFocusTrigger) {
            isListFocused = true
        }
    }

    private var filteredBuckets: [S3Bucket] {
        guard !searchText.isEmpty else { return buckets }
        let query = searchText.lowercased()
        return buckets.filter { $0.name.lowercased().contains(query) }
    }

    private var bucketDeleteDisabled: Bool {
        appState.isReadOnly || selectedBucketIDs.isEmpty || toolbarState.hasSelection
    }

    private var bucketDeleteHelp: String {
        if toolbarState.hasSelection {
            return "Click on the bucket you want to delete — objects are currently selected"
        }
        return selectedBucketIDs.count <= 1 ? "Delete Bucket" : "Delete \(selectedBucketIDs.count) Buckets"
    }

    // MARK: - Header

    private var bucketListHeader: some View {
        ListHeaderBar(
            title: "Buckets",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: buckets.count,
            deleteDisabled: bucketDeleteDisabled,
            deleteHelp: bucketDeleteHelp,
            onRefresh: { loadBuckets(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { bucketsToDelete = buckets.filter { selectedBucketIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var bucketListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: buckets.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading buckets...", onRetry: { loadBuckets(force: true) }, errorContent: { msg in
            S3ConfigHintView(errorMessage: msg, onRetry: { loadBuckets(force: true) })
        }) {
            if buckets.isEmpty {
                EmptyStateView(icon: "externaldrive", message: "No buckets")
                .contextMenu {
                    Button("Create Bucket") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                VStack(spacing: 0) {
                    if buckets.count > 5 {
                        SearchBarView(query: $searchText, placeholder: "Filter buckets", focusTrigger: searchFocusTrigger)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Divider()
                    }
                    List(selection: $selectedBucketIDs) {
                        ForEach(filteredBuckets) { bucket in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bucket.name)
                                    .fontWeight(.medium)
                                if let date = bucket.creationDate {
                                    Text(Self.dateFormatter.string(from: date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .selectionForeground()
                            .tag(bucket.id)
                            .contextMenu {
                                Button("Open in New Window") {
                                    openWindow(value: S3BrowserTarget(bucket: bucket.name, prefix: nil))
                                }
                                Divider()
                                if selectedBucketIDs.count > 1 && selectedBucketIDs.contains(bucket.id) {
                                    let selected = buckets.filter { selectedBucketIDs.contains($0.id) }
                                    let names = selected.map(\.name)
                                    let uris = names.map { "s3://\($0)" }
                                    Button("Copy \(names.count) Names") { copyToClipboard(names.joined(separator: "\n")) }
                                    Button("Copy \(names.count) S3 URIs") { copyToClipboard(uris.joined(separator: "\n")) }
                                } else {
                                    Button("Copy Name") { copyToClipboard(bucket.name) }
                                    Button("Copy S3 URI") { copyToClipboard("s3://\(bucket.name)") }
                                }
                                Divider()
                                Button("Create Bucket") {
                                    showCreateSheet = true
                                }
                                .disabled(appState.isReadOnly)
                                Divider()
                                if selectedBucketIDs.count > 1 && selectedBucketIDs.contains(bucket.id) {
                                    let selected = buckets.filter { selectedBucketIDs.contains($0.id) }
                                    Button("Delete \(selected.count) Buckets", role: .destructive) {
                                        bucketsToDelete = selected
                                    }
                                    .disabled(appState.isReadOnly)
                                } else {
                                    Button("Delete", role: .destructive) {
                                        bucketsToDelete = [bucket]
                                    }
                                    .disabled(appState.isReadOnly)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    bucketsToDelete = [bucket]
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(appState.isReadOnly)
                            }
                        }
                    }
                    .focused($isListFocused)
                    .background(DoubleClickDetector {
                        guard selectedBucketIDs.count == 1 else { return }
                        toolbarState.resetToRootTrigger += 1
                    })
                    .overlay(alignment: .bottom) {
                        if loader.errorMessage != nil {
                            ConnectionLostBanner()
                        }
                    }
                    .contextMenu {
                        Button("Create Bucket") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func loadBuckets(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listBuckets() },
            sort: { a, b in
                switch (a.creationDate, b.creationDate) {
                case let (dateA?, dateB?): return dateA > dateB
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreBucketName,
               let bucket = items.first(where: { $0.name == savedName }) {
                selectedBucketIDs = [bucket.id]
                activeBucket = bucket
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let bucket = items.first(where: { $0.name == name }) {
                selectedBucketIDs = [bucket.id]
                activeBucket = bucket
                pendingSelectName = nil
            }
        }
    }

    private func deleteBuckets(_ targets: [S3Bucket]) {
        Task {
            selectedBucketIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<S3Bucket.ID> = []
            var nonEmptyBuckets: [S3Bucket] = []

            // Delete concurrently so the UI doesn't stall waiting for sequential round-trips
            await withTaskGroup(of: (S3Bucket, Result<Void, Error>).self) { group in
                for bucket in targets {
                    group.addTask { [service] in
                        do {
                            try await service.deleteBucket(name: bucket.name)
                            return (bucket, .success(()))
                        } catch {
                            return (bucket, .failure(error))
                        }
                    }
                }
                for await (bucket, result) in group {
                    switch result {
                    case .success:
                        deletedIDs.insert(bucket.id)
                    case .failure(let error):
                        if let clientError = error as? CloudClientError,
                           let parsed = clientError.serviceError {
                            if parsed.code == "BucketNotEmpty" {
                                nonEmptyBuckets.append(bucket)
                            } else {
                                serviceError = parsed
                            }
                        } else {
                            loader.errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .s3, by: deletedIDs.count)
                selectedBucketIDs.subtract(deletedIDs)
                if let active = activeBucket, deletedIDs.contains(active.id) {
                    activeBucket = nil
                }
                loadBuckets(force: true)
            }
            if !nonEmptyBuckets.isEmpty {
                forceDeleteBuckets = nonEmptyBuckets
            }
        }
    }

    private func performForceDelete(_ targets: [S3Bucket]) {
        isForceDeleting = true
        forceDeleteProgress = 0
        forceDeleteTask?.cancel()
        forceDeleteTask = Task {
            var deletedIDs: Set<S3Bucket.ID> = []
            for bucket in targets {
                guard !Task.isCancelled else { break }
                do {
                    try await service.forceDeleteBucket(bucket: bucket.name) { count in
                        forceDeleteProgress = count
                    }
                    deletedIDs.insert(bucket.id)
                } catch {
                    if let clientError = error as? CloudClientError,
                       let parsed = clientError.serviceError {
                        serviceError = parsed
                    } else if !Task.isCancelled {
                        loader.errorMessage = error.localizedDescription
                    }
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .s3, by: deletedIDs.count)
                selectedBucketIDs.subtract(deletedIDs)
                if let active = activeBucket, deletedIDs.contains(active.id) {
                    activeBucket = nil
                }
            }
            isForceDeleting = false
            loadBuckets(force: true)
        }
    }
}

// MARK: - Force Delete Sheet

private struct ForceDeleteSheet: View {
    let buckets: [S3Bucket]
    @Binding var confirmation: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var isValid: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).lowercased() == "delete"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text(buckets.count == 1 ? "Bucket Not Empty" : "\(buckets.count) Buckets Not Empty")
                    .font(.headline)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if buckets.count == 1, let bucket = buckets.first {
                        Text("\"\(bucket.name)\" contains objects. All objects will be permanently removed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("These buckets contain objects. All objects will be permanently removed:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(buckets) { bucket in
                                Label(bucket.name, systemImage: "externaldrive")
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 200)

            Divider()

            VStack(spacing: 12) {
                TextField("Type \"delete\" to confirm", text: $confirmation)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") { onCancel() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Force Delete", role: .destructive) { onConfirm() }
                        .disabled(!isValid)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 380)
    }
}

/// Detects mouse clicks within its own bounds using an NSEvent monitor.
/// Placed as `.background` on the bucket list pane — doesn't intercept clicks,
/// just observes them to trigger a callback.
private struct PaneClickDetector: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> PaneClickNSView {
        let view = PaneClickNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: PaneClickNSView, context: Context) {
        nsView.onClick = onClick
    }

    final class PaneClickNSView: NSView {
        var onClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor.flatMap { NSEvent.removeMonitor($0) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window == self.window else { return event }
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pointInSelf) {
                    self.onClick?()
                }
                return event
            }
        }

        override func removeFromSuperview() {
            monitor.flatMap { NSEvent.removeMonitor($0) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
