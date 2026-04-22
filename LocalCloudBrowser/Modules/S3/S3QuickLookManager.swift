import Foundation
import AppKit
import Quartz

/// Result of a preview size check.
enum PreviewSizeCheck {
    case allowed
    case overLimit(sizeMB: Int)
    case overHardCap(sizeMB: Int)
}

/// Manages Quick Look preview: download to temp, present QLPreviewPanel, cleanup.
/// Supports ETag-based caching when enabled in preferences.
@MainActor
final class S3QuickLookManager: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double?  // 0.0–1.0 when total is known
    @Published var downloadError: String?

    fileprivate(set) var previewFileURL: URL?
    fileprivate(set) var previewTitle: String?

    private lazy var panelController = QuickLookPanelController(manager: self)
    private var cacheEntries: [PreviewCacheEntry] = []

    init() {
        if AppPreferences.previewCacheEnabled {
            cacheEntries = PreviewCacheIndex.loadIndex(from: AppPreferences.previewTempDirectory)
        }
    }

    /// Check whether a file's size is within limits.
    func checkSize(_ fileSize: Int64, limitBytes: Int64) -> PreviewSizeCheck {
        if fileSize > AppPreferences.previewHardCapBytes {
            return .overHardCap(sizeMB: Int(fileSize / (1024 * 1024)))
        }
        if fileSize > limitBytes {
            return .overLimit(sizeMB: Int(fileSize / (1024 * 1024)))
        }
        return .allowed
    }

    /// Download object to temp and present Quick Look, with ETag caching when enabled.
    func previewObject(bucket: String, key: String, using client: CloudClient) async {
        let filename = key.components(separatedBy: "/").last ?? key
        let cacheDir = AppPreferences.previewTempDirectory
        let cacheEnabled = AppPreferences.previewCacheEnabled

        isDownloading = true
        downloadProgress = nil
        downloadError = nil

        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            let fileURL: URL
            if cacheEnabled {
                let cacheKey = PreviewCacheIndex.CacheKey(
                    endpoint: client.baseURL, bucket: bucket, key: key
                )
                fileURL = try await cachedPreview(
                    cacheKey: cacheKey, bucket: bucket, key: key, filename: filename,
                    cacheDir: cacheDir, client: client
                )
                previewTitle = "\(filename) — Cached Preview"
            } else {
                fileURL = try await downloadToTemp(
                    bucket: bucket, key: key, filename: filename,
                    cacheDir: cacheDir, client: client
                )
                previewTitle = "\(filename) — Temporary Preview"
            }

            previewFileURL = fileURL
            isDownloading = false
            downloadProgress = nil
            showQuickLook()
        } catch {
            isDownloading = false
            downloadProgress = nil
            downloadError = error.localizedDescription
            Log.error("Quick Look download failed: \(error.localizedDescription)", category: "Preview")
        }
    }

    /// Clean up the current preview temp file.
    /// When cache is enabled, keeps the file for future use.
    func cleanupCurrentFile() {
        guard let url = previewFileURL else { return }
        if !AppPreferences.previewCacheEnabled {
            try? FileManager.default.removeItem(at: url)
        }
        previewFileURL = nil
        previewTitle = nil
    }

    /// Current total cache size in bytes.
    var cacheSizeBytes: Int64 {
        PreviewCacheIndex.totalSize(of: cacheEntries, directory: AppPreferences.previewTempDirectory)
    }

    /// Clear all cached preview files and reset the index.
    func clearCache() {
        PreviewCacheIndex.clearAll(directory: AppPreferences.previewTempDirectory)
        cacheEntries = []
    }

    // MARK: - Private: Cache-Aware Download

    /// HEAD → cache check → conditional download. Falls back to full download if HEAD fails.
    private func cachedPreview(
        cacheKey: PreviewCacheIndex.CacheKey, bucket: String, key: String,
        filename: String, cacheDir: URL, client: CloudClient
    ) async throws -> URL {
        // Try HEAD to get current ETag
        let currentETag: String?
        do {
            let headers = try await client.s3Head(path: "/\(bucket)/\(key)")
            currentETag = headers["etag"]
        } catch {
            // HEAD failed — fall back to full download without caching
            Log.info("HEAD request failed, falling back to direct download", category: "Preview")
            return try await downloadToTemp(
                bucket: bucket, key: key, filename: filename,
                cacheDir: cacheDir, client: client
            )
        }

        guard let currentETag, !currentETag.isEmpty else {
            Log.info("No ETag from server, falling back to direct download", category: "Preview")
            return try await downloadToTemp(
                bucket: bucket, key: key, filename: filename,
                cacheDir: cacheDir, client: client
            )
        }

        // Cache hit?
        if let existing = PreviewCacheIndex.lookup(cacheKey, in: cacheEntries, directory: cacheDir),
           existing.etag == currentETag {
            touchEntry(cacheKey: cacheKey)
            let cachedFile = cacheDir.appendingPathComponent(existing.diskFilename)
            Log.info("Preview cache hit: \(filename)", category: "Preview")
            return cachedFile
        }

        // Cache miss — full download to cache location
        let diskFilename = PreviewCacheIndex.diskFilename(for: cacheKey)
        let targetFile = cacheDir.appendingPathComponent(diskFilename)

        try await streamDownload(
            bucket: bucket, key: key, destination: targetFile, client: client
        )

        let fileSize: Int64 = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: targetFile.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }()

        let entry = PreviewCacheEntry(
            endpoint: cacheKey.endpoint, bucket: cacheKey.bucket, key: cacheKey.key,
            etag: currentETag, diskFilename: diskFilename, fileSize: fileSize,
            lastAccessed: Date()
        )
        cacheEntries = PreviewCacheIndex.upsert(entry, in: cacheEntries)

        let maxBytes = Int64(AppPreferences.previewCacheSizeLimitMB) * 1024 * 1024
        cacheEntries = PreviewCacheIndex.evict(
            entries: cacheEntries, directory: cacheDir, maxBytes: maxBytes
        )
        PreviewCacheIndex.saveIndex(cacheEntries, to: cacheDir)
        Log.info("Preview cached: \(filename) (etag: \(currentETag))", category: "Preview")

        return targetFile
    }

    /// Simple non-cached download to a temp file named by the original filename.
    private func downloadToTemp(
        bucket: String, key: String, filename: String,
        cacheDir: URL, client: CloudClient
    ) async throws -> URL {
        let tempFile = cacheDir.appendingPathComponent(filename)
        try await streamDownload(bucket: bucket, key: key, destination: tempFile, client: client)
        return tempFile
    }

    /// Streaming download with progress tracking.
    private func streamDownload(
        bucket: String, key: String, destination: URL, client: CloudClient
    ) async throws {
        let request = try client.buildSignedS3Request(method: "GET", path: "/\(bucket)/\(key)")
        let (bytes, response) = try await client.downloadSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PreviewError.downloadFailed(statusCode: statusCode)
        }

        let totalBytes: Int64? = {
            if let cl = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let n = Int64(cl), n > 0 { return n }
            return nil
        }()

        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        fm.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)

        var downloaded: Int64 = 0
        let chunkSize = 256 * 1024
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                handle.write(buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let total = totalBytes {
                    downloadProgress = Double(downloaded) / Double(total)
                }
            }
        }
        if !buffer.isEmpty {
            handle.write(buffer)
            downloaded += Int64(buffer.count)
        }
        try handle.close()
    }

    /// Updates lastAccessed for an existing cache entry (LRU tracking).
    private func touchEntry(cacheKey: PreviewCacheIndex.CacheKey) {
        guard let idx = cacheEntries.firstIndex(where: {
            $0.endpoint == cacheKey.endpoint && $0.bucket == cacheKey.bucket && $0.key == cacheKey.key
        }) else { return }
        cacheEntries[idx].lastAccessed = Date()
        PreviewCacheIndex.saveIndex(cacheEntries, to: AppPreferences.previewTempDirectory)
    }

    // MARK: - Private

    private func showQuickLook() {
        guard previewFileURL != nil else { return }
        panelController.present()
    }

    enum PreviewError: LocalizedError {
        case invalidURL
        case downloadFailed(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Could not build download URL"
            case .downloadFailed(let code): "Download failed (HTTP \(code))"
            }
        }
    }
}

// MARK: - QLPreviewPanel Controller

/// Handles QLPreviewPanel data source and delegate using @preconcurrency to bridge
/// the nonisolated QL protocols with our @MainActor manager.
@MainActor
final class QuickLookPanelController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private let manager: S3QuickLookManager

    init(manager: S3QuickLookManager) {
        self.manager = manager
        super.init()
    }

    func present() {
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        manager.previewFileURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = manager.previewFileURL else { return nil }
        return QuickLookItem(url: url, title: manager.previewTitle ?? url.lastPathComponent)
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }
}

// MARK: - Preview Item

final class QuickLookItem: NSObject, QLPreviewItem {
    let fileURL: URL
    let title: String

    init(url: URL, title: String) {
        self.fileURL = url
        self.title = title
        super.init()
    }

    var previewItemURL: URL! { fileURL }
    var previewItemTitle: String! { title }
}
