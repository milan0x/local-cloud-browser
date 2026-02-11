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
@MainActor
final class S3QuickLookManager: ObservableObject {
    @Published var isDownloading = false
    @Published var downloadError: String?

    fileprivate(set) var previewFileURL: URL?
    fileprivate(set) var previewTitle: String?

    private lazy var panelController = QuickLookPanelController(manager: self)

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

    /// Download object to temp and present Quick Look.
    func previewObject(bucket: String, key: String, using client: LocalStackClient) async {
        let filename = key.components(separatedBy: "/").last ?? key
        let tempDir = AppPreferences.previewTempDirectory
        let tempFile = tempDir.appendingPathComponent(filename)

        isDownloading = true
        downloadError = nil

        do {
            // Ensure temp directory exists
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Stream download to disk via URLSession
            let url = try buildS3URL(client: client, bucket: bucket, key: key)
            let (downloadedURL, response) = try await URLSession.shared.download(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw PreviewError.downloadFailed(statusCode: statusCode)
            }

            // Move from URLSession temp location to our managed temp folder
            if FileManager.default.fileExists(atPath: tempFile.path) {
                try FileManager.default.removeItem(at: tempFile)
            }
            try FileManager.default.moveItem(at: downloadedURL, to: tempFile)

            previewFileURL = tempFile
            previewTitle = "\(filename) — Temporary Preview"
            isDownloading = false

            showQuickLook()
        } catch {
            isDownloading = false
            downloadError = error.localizedDescription
            Log.error("Quick Look download failed: \(error.localizedDescription)", category: "Preview")
        }
    }

    /// Clean up the current preview temp file.
    func cleanupCurrentFile() {
        guard let url = previewFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        previewFileURL = nil
        previewTitle = nil
    }

    // MARK: - Private

    private func buildS3URL(client: LocalStackClient, bucket: String, key: String) throws -> URL {
        let base = client.s3BaseURL
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let urlString = "\(base)/\(bucket)/\(encodedKey)"
        guard let url = URL(string: urlString) else {
            throw PreviewError.invalidURL
        }
        return url
    }

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
