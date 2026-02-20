import Foundation

struct S3Bucket: Identifiable, Hashable {
    let name: String
    let creationDate: Date?

    var id: String { name }
}

struct S3Object: Identifiable, Hashable {
    let key: String
    let size: Int64
    let lastModified: Date?
    let etag: String
    let storageClass: String

    var id: String { key }

    var isFolder: Bool { key.hasSuffix("/") }

    var displayName: String {
        if isFolder {
            return String(key.dropLast()).components(separatedBy: "/").last ?? key
        }
        return key.components(separatedBy: "/").last ?? key
    }

    var formattedSize: String {
        if isFolder { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct S3ObjectDetail {
    let key: String
    let size: Int64
    let contentType: String
    let lastModified: String
    let etag: String
    let metadata: [String: String]
}

struct S3Prefix: Identifiable, Hashable {
    let prefix: String

    var id: String { prefix }

    var displayName: String {
        let trimmed = String(prefix.dropLast())
        return trimmed.components(separatedBy: "/").last ?? prefix
    }
}
