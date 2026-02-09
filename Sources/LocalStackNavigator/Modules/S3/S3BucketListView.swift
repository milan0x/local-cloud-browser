import SwiftUI

struct S3BucketListView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Binding var selectedBucket: S3Bucket?
    @Binding var showSplitView: Bool
    var onOpenInSplit: ((S3Bucket, String?) -> Void)?

    @Environment(\.openWindow) private var openWindow
    @State private var buckets: [S3Bucket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var bucketToDelete: S3Bucket?
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
        .confirmationDialog(
            "Delete Bucket",
            isPresented: Binding(
                get: { bucketToDelete != nil },
                set: { if !$0 { bucketToDelete = nil } }
            ),
            presenting: bucketToDelete
        ) { bucket in
            Button("Delete \"\(bucket.name)\"", role: .destructive) {
                deleteBucket(bucket)
            }
        } message: { bucket in
            Text("Are you sure you want to delete \"\(bucket.name)\"? This cannot be undone.")
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadBuckets() }
        .onChange(of: appState.connectionVersion) {
            selectedBucket = nil
            buckets = []
            loadBuckets(force: true)
        }
    }

    // MARK: - Header

    private var bucketListHeader: some View {
        HStack {
            Text("Buckets")
                .font(.headline)
            Spacer()

            Button {
                showSplitView.toggle()
            } label: {
                Image(systemName: showSplitView
                    ? "rectangle.split.2x1.fill"
                    : "rectangle.split.2x1")
            }
            .buttonStyle(.borderless)
            .help(showSplitView ? "Close Split View" : "Open Split View")
            .disabled(selectedBucket == nil)

            Button { loadBuckets(force: true) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)
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
        } else {
            List(buckets, selection: $selectedBucket) { bucket in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.name)
                            .fontWeight(.medium)
                        if let date = bucket.creationDate {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        bucketToDelete = bucket
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(appState.isReadOnly ? .gray : .red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isReadOnly)
                }
                .tag(bucket)
                .contextMenu {
                    if let onOpenInSplit {
                        Button("Open in Split View") {
                            onOpenInSplit(bucket, nil)
                        }
                    }
                    Button("Open in New Window") {
                        openWindow(value: S3BrowserTarget(bucket: bucket.name, prefix: nil))
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        bucketToDelete = bucket
                    }
                    .disabled(appState.isReadOnly)
                }
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
                buckets = try await service.listBuckets()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            lastLoadTime = Date()
        }
    }

    private func deleteBucket(_ bucket: S3Bucket) {
        Task {
            do {
                try await service.deleteBucket(name: bucket.name)
                if selectedBucket == bucket { selectedBucket = nil }
                loadBuckets(force: true)
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
