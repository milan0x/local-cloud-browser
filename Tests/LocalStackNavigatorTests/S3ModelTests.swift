import Testing
@testable import LocalStackNavigator

@Suite("S3 Models")
struct S3ModelTests {

    // MARK: - S3Object

    @Test("isFolder detects trailing slash")
    func isFolder() {
        let folder = S3Object(key: "images/", size: 0, lastModified: nil, etag: "", storageClass: "")
        let file = S3Object(key: "photo.jpg", size: 100, lastModified: nil, etag: "", storageClass: "")
        #expect(folder.isFolder == true)
        #expect(file.isFolder == false)
    }

    @Test("displayName extracts file name from key")
    func displayNameFile() {
        let obj = S3Object(key: "path/to/photo.jpg", size: 100, lastModified: nil, etag: "", storageClass: "")
        #expect(obj.displayName == "photo.jpg")
    }

    @Test("displayName extracts folder name from key")
    func displayNameFolder() {
        let obj = S3Object(key: "path/to/images/", size: 0, lastModified: nil, etag: "", storageClass: "")
        #expect(obj.displayName == "images")
    }

    @Test("displayName for root-level file")
    func displayNameRoot() {
        let obj = S3Object(key: "readme.txt", size: 42, lastModified: nil, etag: "", storageClass: "")
        #expect(obj.displayName == "readme.txt")
    }

    @Test("formattedSize returns -- for folders")
    func formattedSizeFolder() {
        let folder = S3Object(key: "dir/", size: 0, lastModified: nil, etag: "", storageClass: "")
        #expect(folder.formattedSize == "--")
    }

    @Test("formattedSize formats bytes for files")
    func formattedSizeFile() {
        let obj = S3Object(key: "file.txt", size: 1024, lastModified: nil, etag: "", storageClass: "")
        #expect(!obj.formattedSize.isEmpty)
        #expect(obj.formattedSize != "--")
    }

    // MARK: - S3Prefix

    @Test("S3Prefix displayName extracts folder name")
    func prefixDisplayName() {
        let prefix = S3Prefix(prefix: "path/to/images/")
        #expect(prefix.displayName == "images")
    }

    @Test("S3Prefix displayName for top-level prefix")
    func prefixDisplayNameTopLevel() {
        let prefix = S3Prefix(prefix: "documents/")
        #expect(prefix.displayName == "documents")
    }
}
