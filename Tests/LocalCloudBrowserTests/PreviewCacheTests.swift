import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Preview Cache")
struct PreviewCacheTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Disk Filename

    @Test("diskFilename is deterministic")
    func deterministicFilename() {
        let key = PreviewCacheIndex.CacheKey(endpoint: "http://localhost", bucket: "b", key: "file.txt")
        let a = PreviewCacheIndex.diskFilename(for: key)
        let b = PreviewCacheIndex.diskFilename(for: key)
        #expect(a == b)
    }

    @Test("diskFilename preserves extension")
    func preserveExtension() {
        let key = PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b", key: "path/image.png")
        let filename = PreviewCacheIndex.diskFilename(for: key)
        #expect(filename.hasSuffix(".png"))
    }

    @Test("diskFilename without extension has no dot")
    func noExtension() {
        let key = PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b", key: "Makefile")
        let filename = PreviewCacheIndex.diskFilename(for: key)
        #expect(!filename.contains("."))
    }

    @Test("Different keys produce different filenames")
    func collisionFree() {
        let key1 = PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b1", key: "file.txt")
        let key2 = PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b2", key: "file.txt")
        #expect(PreviewCacheIndex.diskFilename(for: key1) != PreviewCacheIndex.diskFilename(for: key2))
    }

    // MARK: - Index Persistence

    @Test("Save and load index round-trips")
    func indexRoundTrip() {
        let dir = tempDir()
        defer { cleanup(dir) }

        let entry = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "\"abc\"",
                                       diskFilename: "abc.txt", fileSize: 1024, lastAccessed: Date())
        PreviewCacheIndex.saveIndex([entry], to: dir)
        let loaded = PreviewCacheIndex.loadIndex(from: dir)
        #expect(loaded.count == 1)
        #expect(loaded[0].etag == "\"abc\"")
    }

    @Test("Loading corrupt index returns empty")
    func corruptIndex() {
        let dir = tempDir()
        defer { cleanup(dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "not json".data(using: .utf8)?.write(to: dir.appendingPathComponent("cache-index.json"))
        let loaded = PreviewCacheIndex.loadIndex(from: dir)
        #expect(loaded.isEmpty)
    }

    // MARK: - Lookup

    @Test("Lookup finds matching entry when file exists")
    func lookupHit() {
        let dir = tempDir()
        defer { cleanup(dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = "cached.txt"
        try? "data".data(using: .utf8)?.write(to: dir.appendingPathComponent(filename))

        let entry = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "x",
                                       diskFilename: filename, fileSize: 4, lastAccessed: Date())
        let result = PreviewCacheIndex.lookup(
            PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b", key: "k"),
            in: [entry], directory: dir
        )
        #expect(result != nil)
    }

    @Test("Lookup returns nil when file is missing from disk")
    func lookupMissingFile() {
        let dir = tempDir()
        let entry = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "x",
                                       diskFilename: "gone.txt", fileSize: 4, lastAccessed: Date())
        let result = PreviewCacheIndex.lookup(
            PreviewCacheIndex.CacheKey(endpoint: "e", bucket: "b", key: "k"),
            in: [entry], directory: dir
        )
        #expect(result == nil)
    }

    // MARK: - Upsert

    @Test("Upsert adds new entry")
    func upsertNew() {
        let entry = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "x",
                                       diskFilename: "f.txt", fileSize: 10, lastAccessed: Date())
        let result = PreviewCacheIndex.upsert(entry, in: [])
        #expect(result.count == 1)
    }

    @Test("Upsert replaces existing entry")
    func upsertReplace() {
        let old = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "old",
                                     diskFilename: "f.txt", fileSize: 10, lastAccessed: Date())
        let new = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "k", etag: "new",
                                     diskFilename: "f.txt", fileSize: 20, lastAccessed: Date())
        let result = PreviewCacheIndex.upsert(new, in: [old])
        #expect(result.count == 1)
        #expect(result[0].etag == "new")
    }

    // MARK: - Eviction

    @Test("Eviction removes oldest entries first")
    func evictionOrder() {
        let dir = tempDir()
        defer { cleanup(dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let old = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "old", etag: "x",
                                     diskFilename: "old.txt", fileSize: 100,
                                     lastAccessed: Date(timeIntervalSince1970: 1000))
        let new = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "new", etag: "y",
                                     diskFilename: "new.txt", fileSize: 100,
                                     lastAccessed: Date(timeIntervalSince1970: 2000))
        // Create both files on disk
        try? "x".data(using: .utf8)?.write(to: dir.appendingPathComponent("old.txt"))
        try? "y".data(using: .utf8)?.write(to: dir.appendingPathComponent("new.txt"))

        let result = PreviewCacheIndex.evict(entries: [old, new], directory: dir, maxBytes: 100)
        // Should keep only the newer one
        #expect(result.count == 1)
        #expect(result[0].key == "new")
    }

    // MARK: - Orphan Pruning

    @Test("pruneOrphans removes entries with missing files")
    func pruneOrphans() {
        let dir = tempDir()
        defer { cleanup(dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let exists = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "exists", etag: "x",
                                        diskFilename: "exists.txt", fileSize: 10, lastAccessed: Date())
        let gone = PreviewCacheEntry(endpoint: "e", bucket: "b", key: "gone", etag: "y",
                                      diskFilename: "gone.txt", fileSize: 10, lastAccessed: Date())
        try? "data".data(using: .utf8)?.write(to: dir.appendingPathComponent("exists.txt"))

        let result = PreviewCacheIndex.pruneOrphans(entries: [exists, gone], directory: dir)
        #expect(result.count == 1)
        #expect(result[0].key == "exists")
    }

    // MARK: - Clear All

    @Test("clearAll removes directory")
    func clearAll() {
        let dir = tempDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "data".data(using: .utf8)?.write(to: dir.appendingPathComponent("file.txt"))

        PreviewCacheIndex.clearAll(directory: dir)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}
