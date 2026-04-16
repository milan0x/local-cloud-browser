import Foundation
import CryptoKit

/// Represents a single cached preview file on disk.
struct PreviewCacheEntry: Codable, Equatable, Sendable {
    let endpoint: String
    let bucket: String
    let key: String
    let etag: String
    let diskFilename: String
    let fileSize: Int64
    var lastAccessed: Date

    init(endpoint: String, bucket: String, key: String, etag: String,
         diskFilename: String, fileSize: Int64, lastAccessed: Date) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.key = key
        self.etag = etag
        self.diskFilename = diskFilename
        self.fileSize = fileSize
        self.lastAccessed = lastAccessed
    }
}

/// Pure-logic layer for the preview ETag cache.
/// Manages a JSON-persisted index of cached S3 preview files with LRU eviction.
final class PreviewCacheIndex: Sendable {

    /// Composite key for cache lookups — scoped by endpoint to avoid cross-connection collisions.
    struct CacheKey: Hashable, Sendable {
        let endpoint: String
        let bucket: String
        let key: String

        init(endpoint: String, bucket: String, key: String) {
            self.endpoint = endpoint
            self.bucket = bucket
            self.key = key
        }
    }

    // MARK: - Disk Filename Generation

    /// Generates a unique, filesystem-safe filename for a cache key.
    /// Uses SHA-256 of (endpoint + bucket + key) to avoid collisions,
    /// preserving the original file extension so Quick Look can identify the type.
    static func diskFilename(for cacheKey: CacheKey) -> String {
        let input = "\(cacheKey.endpoint)|\(cacheKey.bucket)|\(cacheKey.key)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        let originalName = cacheKey.key.components(separatedBy: "/").last ?? cacheKey.key
        let ext = (originalName as NSString).pathExtension
        return ext.isEmpty ? hex : "\(hex).\(ext)"
    }

    // MARK: - Index Persistence

    private static let indexFilename = "cache-index.json"

    /// Loads the cache index from a JSON file in the given directory.
    /// Returns an empty array if the file is missing or corrupt.
    static func loadIndex(from directory: URL) -> [PreviewCacheEntry] {
        let indexFile = directory.appendingPathComponent(indexFilename)
        guard let data = try? Data(contentsOf: indexFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PreviewCacheEntry].self, from: data)) ?? []
    }

    /// Saves the cache index to a JSON file in the given directory.
    /// Creates the directory if needed. Silently fails on write errors.
    static func saveIndex(_ entries: [PreviewCacheEntry], to directory: URL) {
        let indexFile = directory.appendingPathComponent(indexFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: indexFile, options: .atomic)
    }

    // MARK: - Lookup

    /// Finds a cache entry matching the given key and returns it (if the file still exists on disk).
    /// Returns nil if not found, or if the cached file was removed by the OS.
    static func lookup(_ cacheKey: CacheKey, in entries: [PreviewCacheEntry],
                       directory: URL) -> PreviewCacheEntry? {
        guard let entry = entries.first(where: {
            $0.endpoint == cacheKey.endpoint && $0.bucket == cacheKey.bucket && $0.key == cacheKey.key
        }) else { return nil }

        let filePath = directory.appendingPathComponent(entry.diskFilename)
        guard FileManager.default.fileExists(atPath: filePath.path) else { return nil }
        return entry
    }

    // MARK: - Insert / Update

    /// Inserts or updates a cache entry. Returns the updated entries array.
    static func upsert(_ entry: PreviewCacheEntry,
                       in entries: [PreviewCacheEntry]) -> [PreviewCacheEntry] {
        var updated = entries.filter {
            !($0.endpoint == entry.endpoint && $0.bucket == entry.bucket && $0.key == entry.key)
        }
        updated.append(entry)
        return updated
    }

    // MARK: - Eviction

    /// Calculates total cached size in bytes from entries whose files still exist on disk.
    static func totalSize(of entries: [PreviewCacheEntry], directory: URL) -> Int64 {
        entries.reduce(into: Int64(0)) { total, entry in
            let filePath = directory.appendingPathComponent(entry.diskFilename)
            if FileManager.default.fileExists(atPath: filePath.path) {
                total += entry.fileSize
            }
        }
    }

    /// Evicts least-recently-accessed entries until total size is at or below the limit.
    /// Deletes evicted files from disk. Returns the surviving entries.
    static func evict(entries: [PreviewCacheEntry], directory: URL,
                      maxBytes: Int64) -> [PreviewCacheEntry] {
        var currentSize = totalSize(of: entries, directory: directory)
        guard currentSize > maxBytes else { return entries }

        // Sort by lastAccessed ascending — oldest first
        var sorted = entries.sorted { $0.lastAccessed < $1.lastAccessed }
        var evicted = Set<String>()

        while currentSize > maxBytes, let oldest = sorted.first {
            sorted.removeFirst()
            let filePath = directory.appendingPathComponent(oldest.diskFilename)
            try? FileManager.default.removeItem(at: filePath)
            currentSize -= oldest.fileSize
            evicted.insert(oldest.diskFilename)
        }

        return entries.filter { !evicted.contains($0.diskFilename) }
    }

    /// Removes orphaned entries whose files no longer exist on disk (OS purged them).
    static func pruneOrphans(entries: [PreviewCacheEntry],
                             directory: URL) -> [PreviewCacheEntry] {
        entries.filter { entry in
            let filePath = directory.appendingPathComponent(entry.diskFilename)
            return FileManager.default.fileExists(atPath: filePath.path)
        }
    }

    /// Removes all cache files and the index file from the given directory.
    static func clearAll(directory: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        try? fm.removeItem(at: directory)
    }
}
