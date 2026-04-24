import Foundation
import UniformTypeIdentifiers

// MARK: - UploadRequest

struct UploadRequest: Sendable {
    let localURL: URL
    let s3Key: String
    let bucket: String
    let size: Int64
    let contentType: String
}

// MARK: - TransferItem

@MainActor
final class TransferItem: Identifiable, ObservableObject {
    let id: UUID
    let fileName: String
    let direction: TransferDirection
    @Published var state: TransferState
    @Published var bytesTransferred: Int64
    @Published var totalBytes: Int64
    var task: Task<Void, Never>?
    let startedAt: Date

    var localURL: URL?
    var s3Key: String?
    var s3Bucket: String?
    var contentType: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        direction: TransferDirection,
        totalBytes: Int64 = 0,
        state: TransferState = .active
    ) {
        self.id = id
        self.fileName = fileName
        self.direction = direction
        self.state = state
        self.bytesTransferred = 0
        self.totalBytes = totalBytes
        self.startedAt = Date()
    }

    var fractionCompleted: Double {
        TransferProgress.fractionCompleted(bytesTransferred: bytesTransferred, totalBytes: totalBytes)
    }

    func updateBytes(bytesTransferred: Int64, totalBytes: Int64) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
    }
}

// MARK: - TransferManager

@MainActor
final class TransferManager: ObservableObject {
    @Published var items: [TransferItem] = []

    private var pendingQueue: [UploadRequest] = []
    private var queueTask: Task<Void, Never>?

    /// Called when a file upload completes — view uses this to append to table.
    var onFileUploaded: ((String, String, Int64) -> Void)?

    /// Called when the entire batch finishes.
    @Published var lastBatchResult: BatchResult?

    /// Set by the transfer detail popover to request navigation to a bucket.
    @Published var navigateToBucket: String?

    enum BatchResult: Equatable {
        case completed(bucket: String)
        case cancelled(bucket: String)
        case failed(bucket: String, failedCount: Int, totalCount: Int)
    }

    var activeCount: Int {
        items.filter { $0.state == .active }.count
    }

    var queuedCount: Int {
        items.filter { $0.state == .queued }.count
    }

    var completedCount: Int {
        items.filter { $0.state == .completed }.count
    }

    var failedCount: Int {
        items.filter { if case .failed = $0.state { return true } else { return false } }.count
    }

    var totalBatchCount: Int {
        items.filter { !$0.state.isFinished || $0.state == .completed }.count
    }

    var pendingFileCount: Int { pendingQueue.count }

    var pendingBytes: Int64 { pendingQueue.reduce(0) { $0 + $1.size } }

    var hasActiveTransfers: Bool {
        items.contains { $0.state == .active || $0.state == .queued } || !pendingQueue.isEmpty
    }

    var activeDirection: TransferDirection {
        items.first { $0.state == .active || $0.state == .queued }?.direction ?? .upload
    }

    var totalFileCount: Int {
        let enqueued = items.filter { $0.state == .active || $0.state == .queued || $0.state == .completed }.count
        return enqueued + pendingQueue.count
    }

    var overallProgress: Double {
        let relevant = items.filter { $0.state == .active || $0.state == .completed || $0.state == .queued }
        let enqueuedTotal = relevant.reduce(Int64(0)) { $0 + $1.totalBytes }
        let transferred = relevant.reduce(Int64(0)) { $0 + $1.bytesTransferred }
        let totalBytes = enqueuedTotal + pendingBytes
        guard totalBytes > 0 else { return 0 }
        return min(Double(transferred) / Double(totalBytes), 1.0)
    }

    // MARK: - Per-Bucket Queries

    func hasActiveTransfersForBucket(_ name: String) -> Bool {
        items.contains { ($0.s3Bucket == name) && ($0.state == .active || $0.state == .queued) }
            || pendingQueue.contains { $0.bucket == name }
    }

    func queuePositionForBucket(_ name: String) -> (pendingFiles: Int, filesAhead: Int, bucketsAhead: Int, isActive: Bool) {
        let isActive = items.contains { $0.s3Bucket == name && $0.state == .active }
        let pendingForBucket = pendingQueue.filter { $0.bucket == name }.count
        var filesAhead = 0
        var bucketsAheadSet = Set<String>()
        for req in pendingQueue {
            if req.bucket == name { break }
            filesAhead += 1
            bucketsAheadSet.insert(req.bucket)
        }
        for item in items where item.state == .active || item.state == .queued {
            if let b = item.s3Bucket, b != name {
                bucketsAheadSet.insert(b)
            }
        }
        return (pendingFiles: pendingForBucket, filesAhead: filesAhead, bucketsAhead: bucketsAheadSet.count, isActive: isActive)
    }

    func totalFileCountForBucket(_ name: String) -> Int {
        let enqueued = items.filter { $0.s3Bucket == name && ($0.state == .active || $0.state == .queued || $0.state == .completed) }.count
        let pending = pendingQueue.filter { $0.bucket == name }.count
        return enqueued + pending
    }

    func completedCountForBucket(_ name: String) -> Int {
        items.filter { $0.s3Bucket == name && $0.state == .completed }.count
    }

    func failedCountForBucket(_ name: String) -> Int {
        items.filter { item in
            guard item.s3Bucket == name else { return false }
            if case .failed = item.state { return true }
            return false
        }.count
    }

    func progressForBucket(_ name: String) -> Double {
        let relevant = items.filter { $0.s3Bucket == name && ($0.state == .active || $0.state == .completed || $0.state == .queued) }
        let enqueuedTotal = relevant.reduce(Int64(0)) { $0 + $1.totalBytes }
        let transferred = relevant.reduce(Int64(0)) { $0 + $1.bytesTransferred }
        let pendingBucketBytes = pendingQueue.filter { $0.bucket == name }.reduce(Int64(0)) { $0 + $1.size }
        let totalBytes = enqueuedTotal + pendingBucketBytes
        guard totalBytes > 0 else { return 0 }
        return min(Double(transferred) / Double(totalBytes), 1.0)
    }

    var activeBucketCount: Int {
        var buckets = Set(items.filter { $0.state == .active || $0.state == .queued }.compactMap(\.s3Bucket))
        buckets.formUnion(pendingQueue.map(\.bucket))
        return buckets.count
    }

    var completedBucketCount: Int {
        let allBuckets = Set(items.compactMap(\.s3Bucket))
        return allBuckets.filter { bucket in
            !items.contains { $0.s3Bucket == bucket && ($0.state == .active || $0.state == .queued) }
                && !pendingQueue.contains { $0.bucket == bucket }
        }.count
    }

    var totalBucketCount: Int {
        var buckets = Set(items.compactMap(\.s3Bucket))
        buckets.formUnion(pendingQueue.map(\.bucket))
        return buckets.count
    }

    var summaryText: String {
        let active = items.filter { $0.state == .active || $0.state == .queued || $0.state == .completed }
        guard !active.isEmpty else { return "" }

        let finished = active.filter { $0.state == .completed }.count
        let total = active.count
        let direction = active.first { $0.state == .active }?.direction ?? active.first?.direction ?? .upload
        let verb = direction == .upload ? "Uploading" : "Downloading"
        let pct = Int(overallProgress * 100)

        if total == 1 {
            return "\(verb) \u{2014} \(pct)%"
        } else {
            return "\(verb) \(finished)/\(total) \u{2014} \(pct)%"
        }
    }

    @discardableResult
    func add(fileName: String, direction: TransferDirection, totalBytes: Int64 = 0, state: TransferState = .active) -> TransferItem {
        let item = TransferItem(fileName: fileName, direction: direction, totalBytes: totalBytes, state: state)
        items.insert(item, at: 0)
        return item
    }

    var isProcessingQueue = false

    // MARK: - Upload Queue

    func enqueueUploads(
        _ files: [UploadRequest],
        uploadHandler: @escaping @Sendable (UploadRequest, UUID, @escaping @Sendable (Int64, Int64) -> Void) async throws -> Void
    ) {
        if !isProcessingQueue {
            clearAll()
            lastBatchResult = nil
        }
        pendingQueue.append(contentsOf: files)
        objectWillChange.send()
        if !isProcessingQueue {
            queueTask = Task { await processQueue(uploadHandler: uploadHandler) }
        }
    }

    private func processQueue(
        uploadHandler: @escaping @Sendable (UploadRequest, UUID, @escaping @Sendable (Int64, Int64) -> Void) async throws -> Void
    ) async {
        isProcessingQueue = true

        let maxConcurrency = 6
        let (slotStream, slotContinuation) = AsyncStream.makeStream(of: Void.self)
        var activeCount = 0
        var batchBucket = ""

        while !pendingQueue.isEmpty || activeCount > 0 {
            while activeCount < maxConcurrency && !pendingQueue.isEmpty {
                if Task.isCancelled {
                    cancelAll()
                    slotContinuation.finish()
                    break
                }

                let request = pendingQueue.removeFirst()
                batchBucket = request.bucket
                objectWillChange.send()

                let item = add(fileName: request.localURL.lastPathComponent, direction: .upload, totalBytes: request.size, state: .active)
                item.s3Key = request.s3Key
                item.s3Bucket = request.bucket
                item.contentType = request.contentType

                activeCount += 1
                let itemID = item.id
                let key = request.s3Key
                let size = request.size
                let bucket = request.bucket

                // Store the upload Task on the item so `cancel(id:)`,
                // `cancelForBucket(_:)`, and `cancelAll()` can actually
                // cancel it. Previously this Task was fire-and-forget: the
                // reference was discarded, item.task stayed nil, and every
                // cancel path silently no-op'd — the pill's X, the popover
                // Cancel-All button, and the per-row X all just updated
                // state to .cancelled while the upload kept running
                // until the underlying URLSession task finished on its own.
                let uploadTask = Task { [weak self] in
                    do {
                        try Task.checkCancellation()
                        try await uploadHandler(request, itemID) { [weak self] bytesSent, totalBytes in
                            Task { @MainActor [weak self] in
                                self?.updateProgress(id: itemID, bytesTransferred: bytesSent, totalBytes: totalBytes)
                            }
                        }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            // Check the item state BEFORE committing the
                            // completion. If cancel(id:) fired while the
                            // network was draining the last bytes, the item
                            // is already .cancelled — don't flip it back to
                            // .completed and don't fire onFileUploaded, or
                            // the file list shows a row the user thinks
                            // they cancelled.
                            guard let item = self.items.first(where: { $0.id == itemID }),
                                  item.state == .active else { return }
                            self.complete(id: itemID)
                            self.onFileUploaded?(bucket, key, size)
                        }
                    } catch is CancellationError {
                        await MainActor.run { [weak self] in self?.cancel(id: itemID) }
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        // URLSession.data/upload throws URLError(.cancelled)
                        // (not CancellationError) when the enclosing Task is
                        // cancelled — route it to the cancelled state, not
                        // the failed state, so the UI stays clean.
                        await MainActor.run { [weak self] in self?.cancel(id: itemID) }
                    } catch {
                        await MainActor.run { [weak self] in self?.fail(id: itemID, message: error.localizedDescription) }
                    }
                    slotContinuation.yield()
                }
                item.task = uploadTask
            }

            if Task.isCancelled {
                cancelAll()
                break
            }

            if activeCount > 0 {
                var iterator = slotStream.makeAsyncIterator()
                await iterator.next()
                activeCount -= 1
            }
        }

        slotContinuation.finish()
        let hasRemaining = items.contains(where: { $0.state == .active || $0.state == .queued })
        let wasCancelled = items.contains(where: { $0.state == .cancelled })
        let failed = failedCount
        let total = items.count

        isProcessingQueue = false

        if !hasRemaining {
            if wasCancelled {
                lastBatchResult = .cancelled(bucket: batchBucket)
            } else if failed > 0 {
                lastBatchResult = .failed(bucket: batchBucket, failedCount: failed, totalCount: total)
            } else {
                lastBatchResult = .completed(bucket: batchBucket)
            }
        }
    }

    // MARK: - Progress & State

    func updateProgress(id: UUID, bytesTransferred: Int64, totalBytes: Int64) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.state == .active else { return }
        let prevBytes = item.bytesTransferred
        item.updateBytes(bytesTransferred: bytesTransferred, totalBytes: totalBytes)
        if item.bytesTransferred != prevBytes {
            objectWillChange.send()
        }
    }

    func complete(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.state = .completed
        if item.totalBytes > 0 {
            item.bytesTransferred = item.totalBytes
        }
        // Release the Task reference so captured credentials, file handles,
        // and upload handler closures can be deallocated. Without this, every
        // completed TransferItem held a live Task until items was cleared,
        // growing unbounded over the app session.
        item.task = nil
        objectWillChange.send()
    }

    func fail(id: UUID, message: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.state = .failed(message)
        item.task = nil
        objectWillChange.send()
    }

    func cancel(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.task?.cancel()
        item.task = nil
        item.state = .cancelled
        objectWillChange.send()
    }

    func cancelAll() {
        pendingQueue.removeAll()
        queueTask?.cancel()
        for item in items where item.state == .active || item.state == .queued {
            item.task?.cancel()
            item.task = nil
            item.state = .cancelled
        }
        objectWillChange.send()
    }

    func cancelForBucket(_ name: String) {
        pendingQueue.removeAll { $0.bucket == name }
        for item in items where item.s3Bucket == name && (item.state == .active || item.state == .queued) {
            item.task?.cancel()
            item.task = nil
            item.state = .cancelled
        }
        objectWillChange.send()
    }

    var activeBucketNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for item in items where item.state == .active || item.state == .queued {
            if let bucket = item.s3Bucket, seen.insert(bucket).inserted {
                names.append(bucket)
            }
        }
        for req in pendingQueue {
            if seen.insert(req.bucket).inserted {
                names.append(req.bucket)
            }
        }
        return names
    }

    func clearCompleted() {
        items.removeAll { $0.state.isFinished }
    }

    func clearAll() {
        items.removeAll()
    }
}
