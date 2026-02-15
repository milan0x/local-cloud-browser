import SwiftUI
import AppKit

struct S3BucketListView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Binding var selectedBucketIDs: Set<S3Bucket.ID>
    @Binding var activeBucket: S3Bucket?
    @ObservedObject var toolbarState: S3ToolbarState
    var restoreBucketName: String?

    @Environment(\.openWindow) private var openWindow
    @State private var buckets: [S3Bucket] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var bucketsToDelete: [S3Bucket] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var forceDeleteBuckets: [S3Bucket] = []
    @State private var forceDeleteConfirmation = ""
    @State private var isForceDeleting = false

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
                            ProgressView("Deleting...")
                        }
                    }
                }
        }
        .disabled(isForceDeleting)
        .background(PaneClickDetector {
            toolbarState.clearSelectionTrigger += 1
        })
        .sheet(isPresented: $showCreateSheet) {
            S3CreateBucketView(service: service, existingBucketNames: Set(buckets.map(\.name)))
                .onDisappear { loadBuckets(force: true) }
        }
        .alert(
            bucketsToDelete.count == 1
                ? "Delete Bucket"
                : "Delete \(bucketsToDelete.count) Buckets",
            isPresented: Binding(
                get: { !bucketsToDelete.isEmpty },
                set: { if !$0 { bucketsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteBuckets(bucketsToDelete)
            }
            Button("Cancel", role: .cancel) {
                bucketsToDelete = []
            }
        } message: {
            if bucketsToDelete.count == 1, let bucket = bucketsToDelete.first {
                Text("Are you sure you want to delete \"\(bucket.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = bucketsToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these buckets?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .alert(
            forceDeleteBuckets.count == 1
                ? "Bucket Not Empty"
                : "Buckets Not Empty",
            isPresented: Binding(
                get: { !forceDeleteBuckets.isEmpty },
                set: { if !$0 { forceDeleteBuckets = []; forceDeleteConfirmation = "" } }
            )
        ) {
            TextField("Type delete to confirm", text: $forceDeleteConfirmation)
            Button("Force Delete", role: .destructive) {
                let trimmed = forceDeleteConfirmation.trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed == "delete" {
                    let targets = forceDeleteBuckets
                    forceDeleteBuckets = []
                    forceDeleteConfirmation = ""
                    performForceDelete(targets)
                } else {
                    let targets = forceDeleteBuckets
                    forceDeleteBuckets = []
                    forceDeleteConfirmation = ""
                    DispatchQueue.main.async {
                        forceDeleteBuckets = targets
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                forceDeleteBuckets = []
                forceDeleteConfirmation = ""
            }
        } message: {
            if forceDeleteBuckets.count == 1, let bucket = forceDeleteBuckets.first {
                Text("\"\(bucket.name)\" contains objects. Type \"delete\" to permanently remove all objects and delete the bucket.")
            } else {
                let names = forceDeleteBuckets.map(\.name).joined(separator: ", ")
                Text("\(names) contain objects. Type \"delete\" to permanently remove all objects and delete the buckets.")
            }
        }
        .task { loadBuckets() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && bucketsToDelete.isEmpty && forceDeleteBuckets.isEmpty && !isForceDeleting && !isLoading else { return }
            loadBuckets(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedBucketIDs = []
            activeBucket = nil
            buckets = []
            loadBuckets(force: true)
        }
        .onChange(of: selectedBucketIDs) {
            if selectedBucketIDs.count == 1, let id = selectedBucketIDs.first {
                activeBucket = buckets.first { $0.id == id }
            } else {
                activeBucket = nil
            }
        }
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
        HStack {
            Text("Buckets")
                .font(.headline)
            Text("Global")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadBuckets(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadBuckets(force: true)
            }

            Button {
                bucketsToDelete = buckets.filter { selectedBucketIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(bucketDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(bucketDeleteDisabled)
            .help(bucketDeleteHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var bucketListContent: some View {
        if isLoading && buckets.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading buckets...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadBuckets(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if buckets.isEmpty {
            EmptyStateView(icon: "externaldrive", message: "No buckets")
            .contextMenu {
                Button("Create Bucket") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            List(buckets, selection: $selectedBucketIDs) { bucket in
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .fontWeight(.medium)
                    if let date = bucket.creationDate {
                        Text(Self.dateFormatter.string(from: date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
            }
            .overlay(alignment: .bottom) {
                if errorMessage != nil {
                    connectionLostBanner
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

    private var connectionLostBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost — showing cached data")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
    }

    // MARK: - Data

    private func loadBuckets(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let freshBuckets = try await service.listBuckets().sorted { a, b in
                    switch (a.creationDate, b.creationDate) {
                    case let (dateA?, dateB?): return dateA > dateB
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                    }
                }
                if buckets != freshBuckets {
                    buckets = freshBuckets
                }
                if !hasRestoredSession, let savedName = restoreBucketName,
                   let bucket = buckets.first(where: { $0.name == savedName }) {
                    selectedBucketIDs = [bucket.id]
                    activeBucket = bucket
                }
                hasRestoredSession = true
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func deleteBuckets(_ targets: [S3Bucket]) {
        Task {
            var deletedIDs: Set<S3Bucket.ID> = []
            var nonEmptyBuckets: [S3Bucket] = []
            for bucket in targets {
                do {
                    try await service.deleteBucket(name: bucket.name)
                    deletedIDs.insert(bucket.id)
                } catch {
                    if let clientError = error as? LocalStackClientError,
                       let parsed = clientError.serviceError {
                        if parsed.code == "BucketNotEmpty" {
                            nonEmptyBuckets.append(bucket)
                        } else {
                            serviceError = parsed
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            if !deletedIDs.isEmpty {
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
        Task {
            var deletedIDs: Set<S3Bucket.ID> = []
            for bucket in targets {
                do {
                    try await service.forceDeleteBucket(bucket: bucket.name)
                    deletedIDs.insert(bucket.id)
                } catch {
                    if let clientError = error as? LocalStackClientError,
                       let parsed = clientError.serviceError {
                        serviceError = parsed
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            if !deletedIDs.isEmpty {
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
