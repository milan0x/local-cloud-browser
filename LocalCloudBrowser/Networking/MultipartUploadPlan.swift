import Foundation

// MARK: - Upload Part Planning

struct UploadPartRange: Sendable {
    let partNumber: Int
    let offset: Int64
    let length: Int

    init(partNumber: Int, offset: Int64, length: Int) {
        self.partNumber = partNumber
        self.offset = offset
        self.length = length
    }
}

struct CompletedPart: Sendable {
    let partNumber: Int
    let etag: String

    nonisolated init(partNumber: Int, etag: String) {
        self.partNumber = partNumber
        self.etag = etag
    }
}

struct MultipartUploadPlan: Sendable {
    let parts: [UploadPartRange]
    let partSize: Int
    let fileSize: Int64
    let isMultipart: Bool

    init(parts: [UploadPartRange], partSize: Int, fileSize: Int64, isMultipart: Bool) {
        self.parts = parts
        self.partSize = partSize
        self.fileSize = fileSize
        self.isMultipart = isMultipart
    }

    /// Minimum S3 part size (5 MB), except for the last part.
    static let minimumPartSize = 5 * 1024 * 1024

    /// Maximum number of parts S3 allows.
    static let maximumPartCount = 10_000

    /// Default preferred part size (8 MB).
    static let defaultPartSize = 8 * 1024 * 1024

    /// Creates an upload plan for a file of the given size.
    ///
    /// Files <= `minimumPartSize` use a single PUT (no multipart).
    /// Larger files are split into parts of `preferredPartSize`, scaled up
    /// if needed to stay within the 10,000 part limit.
    static func plan(fileSize: Int64, preferredPartSize: Int = defaultPartSize) -> MultipartUploadPlan {
        guard fileSize > Int64(minimumPartSize) else {
            return MultipartUploadPlan(
                parts: [UploadPartRange(partNumber: 1, offset: 0, length: Int(fileSize))],
                partSize: Int(fileSize),
                fileSize: fileSize,
                isMultipart: false
            )
        }

        var partSize = max(preferredPartSize, minimumPartSize)

        // Scale up part size if we'd exceed the max part count
        while fileSize / Int64(partSize) > Int64(maximumPartCount - 1) {
            partSize *= 2
        }

        var parts: [UploadPartRange] = []
        var offset: Int64 = 0
        var partNumber = 1

        while offset < fileSize {
            let remaining = fileSize - offset
            let length = Int(min(Int64(partSize), remaining))
            parts.append(UploadPartRange(partNumber: partNumber, offset: offset, length: length))
            offset += Int64(length)
            partNumber += 1
        }

        return MultipartUploadPlan(
            parts: parts,
            partSize: partSize,
            fileSize: fileSize,
            isMultipart: true
        )
    }

    /// Builds the XML body for CompleteMultipartUpload.
    static func completeMultipartXML(parts: [CompletedPart]) -> Data {
        var xml = "<CompleteMultipartUpload>"
        for part in parts.sorted(by: { $0.partNumber < $1.partNumber }) {
            xml += "<Part>"
            xml += "<PartNumber>\(part.partNumber)</PartNumber>"
            xml += "<ETag>\(part.etag)</ETag>"
            xml += "</Part>"
        }
        xml += "</CompleteMultipartUpload>"
        return Data(xml.utf8)
    }
}
