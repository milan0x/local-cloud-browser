import SwiftUI
import AppKit

struct S3BucketListView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var autoRefresh: AutoRefreshManager
    @Binding var selectedBucketIDs: Set<S3Bucket.ID>
    @Binding var activeBucket: S3Bucket?

    @Environment(\.openWindow) private var openWindow
    @State private var buckets: [S3Bucket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var bucketsToDelete: [S3Bucket] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?

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
        }
        .sheet(isPresented: $showCreateSheet) {
            S3CreateBucketView(service: service)
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
        .task { loadBuckets() }
        .onChange(of: autoRefresh.refreshTrigger) {
            guard !showCreateSheet && bucketsToDelete.isEmpty && !isLoading else { return }
            loadBuckets(force: true)
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

    // MARK: - Header

    private var bucketListHeader: some View {
        HStack {
            Text("Buckets")
                .font(.headline)
            Text("Global")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            AutoRefreshIndicatorView(manager: autoRefresh) {
                loadBuckets(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: $autoRefresh.interval) {
                loadBuckets(force: true)
            }

            Button {
                bucketsToDelete = buckets.filter { selectedBucketIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(appState.isReadOnly || selectedBucketIDs.isEmpty ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly || selectedBucketIDs.isEmpty)
            .help(selectedBucketIDs.count <= 1 ? "Delete Bucket" : "Delete \(selectedBucketIDs.count) Buckets")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var bucketListContent: some View {
        if isLoading && buckets.isEmpty {
            ProgressView("Loading buckets...")
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
            VStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No buckets")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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
            .contextMenu {
                Button("Create Bucket") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        }
    }

    // MARK: - Data

    private func loadBuckets(force: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                buckets = try await service.listBuckets().sorted { a, b in
                    switch (a.creationDate, b.creationDate) {
                    case let (dateA?, dateB?): return dateA > dateB
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            lastLoadTime = Date()
        }
    }

    private func deleteBuckets(_ targets: [S3Bucket]) {
        Task {
            var deletedIDs: Set<S3Bucket.ID> = []
            for bucket in targets {
                do {
                    try await service.deleteBucket(name: bucket.name)
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
                loadBuckets(force: true)
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
