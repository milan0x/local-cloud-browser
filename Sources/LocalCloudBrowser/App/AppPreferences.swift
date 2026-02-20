import Foundation

enum AppPreferences {
    static let showFolderDetailsOnDeleteKey = "showFolderDetailsOnDelete"
    static let autoRefreshIntervalKey = "autoRefreshInterval"
    static let previewSizeLimitMBKey = "previewSizeLimitMB"
    static let restoreLastSessionKey = "restoreLastSession"
    static let healthCheckIntervalKey = "healthCheckInterval"
    static let doubleClickHidesJsonHelperKey = "doubleClickHidesJsonHelper"
    static let disableJsonHelperPlaceholdersKey = "disableSQSPlaceholders"
    static let defaultHealthCheckInterval: Double = 2.0

    /// Default preview size limit in megabytes.
    static let defaultPreviewSizeLimitMB = 10
    /// Hard cap in bytes — not configurable, protects against excessive downloads.
    static let previewHardCapBytes: Int64 = 300 * 1024 * 1024

    /// Dedicated temp subfolder for Quick Look preview files.
    static let previewTempSubfolder = "localcloudbrowser-preview"

    static var previewTempDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(previewTempSubfolder, isDirectory: true)
    }

    /// Wipe the entire preview temp folder (call on app launch).
    static func cleanPreviewTempDirectory() {
        let fm = FileManager.default
        let dir = previewTempDirectory
        if fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
        }
    }
}
