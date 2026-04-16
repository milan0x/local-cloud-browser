import Foundation

enum AppPreferences {
    static let showFolderDetailsOnDeleteKey = "showFolderDetailsOnDelete"
    static let autoRefreshIntervalKey = "autoRefreshInterval"
    static let previewSizeLimitMBKey = "previewSizeLimitMB"
    static let restoreLastSessionKey = "restoreLastSession"
    static let healthCheckIntervalKey = "healthCheckInterval"
    static let isReadOnlyKey = "isReadOnly"
    static let doubleClickHidesJsonHelperKey = "doubleClickHidesJsonHelper"
    static let disableJsonHelperPlaceholdersKey = "disableSQSPlaceholders"
    static let doubleClickActionKey = "doubleClickAction"
    static let previewCacheEnabledKey = "previewCacheEnabled"
    static let previewCacheSizeLimitMBKey = "previewCacheSizeLimitMB"
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

    /// Default preview cache size limit in megabytes.
    static let defaultPreviewCacheSizeLimitMB = 500

    static var previewCacheEnabled: Bool {
        // Default to true if never set
        if UserDefaults.standard.object(forKey: previewCacheEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: previewCacheEnabledKey)
    }

    static var previewCacheSizeLimitMB: Int {
        let stored = UserDefaults.standard.integer(forKey: previewCacheSizeLimitMBKey)
        return stored > 0 ? stored : defaultPreviewCacheSizeLimitMB
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
