import Foundation
import CryptoKit

final class S3Service: BaseService {

    /// Default part size for multipart uploads: 10 MB
    private static let defaultPartSize = 10 * 1024 * 1024
    /// Files larger than this threshold use multipart upload: 20 MB
    private static let multipartThreshold: Int64 = 20 * 1024 * 1024

    func listBuckets() async throws -> [S3Bucket] {
        let data = try await client.s3Request(method: "GET", path: "/")
        return try S3BucketListParser().parse(data: data)
    }

    func createBucket(name: String, region: String? = nil) async throws {
        var body: Data?
        var contentType: String?
        if let region, !region.isEmpty, region != "us-east-1" {
            let xml = """
                <CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
                    <LocationConstraint>\(region)</LocationConstraint>
                </CreateBucketConfiguration>
                """
            body = Data(xml.utf8)
            contentType = "application/xml"
        }
        _ = try await client.s3Request(method: "PUT", path: "/\(name)", body: body, contentType: contentType)
    }

    func deleteBucket(name: String) async throws {
        _ = try await client.s3Request(method: "DELETE", path: "/\(name)")
    }

    func listObjects(bucket: String, prefix: String = "", continuationToken: String? = nil) async throws -> S3ObjectListResult {
        var params: [String: String] = ["list-type": "2", "delimiter": "/"]
        if !prefix.isEmpty {
            params["prefix"] = prefix
        }
        if let continuationToken {
            params["continuation-token"] = continuationToken
        }
        let data = try await client.s3Request(
            method: "GET",
            path: "/\(bucket)",
            queryParams: params
        )
        return try S3ObjectListParser().parse(data: data)
    }

    func listAllFolderContents(bucket: String, prefix: String) async throws -> (objects: [S3Object], prefixes: [S3Prefix]) {
        var allObjects: [S3Object] = []
        var allPrefixes: [S3Prefix] = []
        var token: String? = nil
        repeat {
            let result = try await listObjects(bucket: bucket, prefix: prefix, continuationToken: token)
            allObjects.append(contentsOf: result.objects)
            allPrefixes.append(contentsOf: result.commonPrefixes)
            token = result.isTruncated ? result.nextContinuationToken : nil
            if allObjects.count >= 10_000 { break }
        } while token != nil
        return (objects: allObjects, prefixes: allPrefixes)
    }

    func listAllObjects(bucket: String, prefix: String) async throws -> [S3Object] {
        var allObjects: [S3Object] = []
        var token: String? = nil
        repeat {
            var params: [String: String] = ["list-type": "2", "prefix": prefix]
            if let token { params["continuation-token"] = token }
            let data = try await client.s3Request(method: "GET", path: "/\(bucket)", queryParams: params)
            let result = try S3ObjectListParser().parse(data: data)
            allObjects.append(contentsOf: result.objects)
            token = result.isTruncated ? result.nextContinuationToken : nil
            if allObjects.count >= 10_000 { break }
        } while token != nil
        return allObjects
    }

    func getObject(bucket: String, key: String) async throws -> Data {
        try await client.s3Request(method: "GET", path: "/\(bucket)/\(key)")
    }

    /// Downloads an object directly to a file using streaming (no full in-memory buffering).
    /// Uses URLSession.download with a signed request for production S3 compatibility.
    func downloadObjectToFile(bucket: String, key: String, destination: URL) async throws {
        let request = try client.buildSignedS3Request(method: "GET", path: "/\(bucket)/\(key)")
        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudClientError.invalidURL
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            let errorData = (try? Data(contentsOf: tempURL)) ?? Data()
            throw CloudClientError.httpError(statusCode: httpResponse.statusCode, data: errorData)
        }

        // Move from URLSession temp location to destination
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
    }

    func putObject(bucket: String, key: String, data: Data, contentType: String) async throws {
        _ = try await client.s3Request(
            method: "PUT",
            path: "/\(bucket)/\(key)",
            body: data,
            contentType: contentType
        )
    }

    // MARK: - Multipart Upload

    /// Initiates a multipart upload and returns the upload ID.
    func createMultipartUpload(bucket: String, key: String, contentType: String) async throws -> String {
        let data = try await client.s3Request(
            method: "POST",
            path: "/\(bucket)/\(key)",
            queryParams: ["uploads": ""],
            contentType: contentType
        )
        return try S3InitiateMultipartUploadParser().parse(data: data)
    }

    /// Uploads a single part and returns its ETag.
    func uploadPart(bucket: String, key: String, uploadId: String, partNumber: Int, data: Data, useUnsignedPayload: Bool = false) async throws -> String {
        var headers: [String: String] = [:]
        // Content-MD5 for transfer integrity on non-local endpoints
        if useUnsignedPayload {
            headers["Content-MD5"] = SigV4Signer.md5Base64(data)
        }
        let response = try await client.s3RequestWithHeaders(
            method: "PUT",
            path: "/\(bucket)/\(key)",
            queryParams: ["partNumber": "\(partNumber)", "uploadId": uploadId],
            body: data,
            contentType: "application/octet-stream",
            headers: headers,
            unsignedPayload: useUnsignedPayload
        )
        guard let etag = response.headers["etag"] else {
            throw S3XMLParserError.parseFailed("Missing ETag in uploadPart response")
        }
        return etag
    }

    /// Completes a multipart upload by sending the list of parts.
    func completeMultipartUpload(bucket: String, key: String, uploadId: String, parts: [(partNumber: Int, etag: String)]) async throws {
        var xml = "<CompleteMultipartUpload>"
        for part in parts {
            xml += "<Part><PartNumber>\(part.partNumber)</PartNumber><ETag>\(part.etag)</ETag></Part>"
        }
        xml += "</CompleteMultipartUpload>"
        _ = try await client.s3Request(
            method: "POST",
            path: "/\(bucket)/\(key)",
            queryParams: ["uploadId": uploadId],
            body: Data(xml.utf8),
            contentType: "application/xml"
        )
    }

    /// Aborts a multipart upload, cleaning up uploaded parts on the server.
    func abortMultipartUpload(bucket: String, key: String, uploadId: String) async throws {
        _ = try await client.s3Request(
            method: "DELETE",
            path: "/\(bucket)/\(key)",
            queryParams: ["uploadId": uploadId]
        )
    }

    /// Maximum number of concurrent part uploads (bounds memory to maxConcurrentParts × partSize).
    private static let maxConcurrentParts = 4

    /// Uploads a file using multipart upload with FileHandle-based chunking
    /// and concurrent part uploads. Reads are sequential (FileHandle is not Sendable),
    /// but up to `maxConcurrentParts` network uploads run in parallel.
    /// Peak memory: ~maxConcurrentParts × partSize (40 MB with defaults).
    func putObjectMultipart(
        bucket: String,
        key: String,
        fileURL: URL,
        contentType: String,
        partSize: Int = S3Service.defaultPartSize,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let fileSize = try Int64(fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let uploadId = try await createMultipartUpload(bucket: bucket, key: key, contentType: contentType)
        let useUnsigned = !client.isLocalEndpoint

        do {
            var completedParts: [(partNumber: Int, etag: String)] = []
            var nextPartNumber = 1
            var bytesUploaded: Int64 = 0

            try await withThrowingTaskGroup(of: (Int, String, Int).self) { group in
                // Seed initial concurrent uploads
                for _ in 0..<Self.maxConcurrentParts {
                    guard let chunk = try fileHandle.read(upToCount: partSize), !chunk.isEmpty else { break }
                    let pn = nextPartNumber
                    let chunkSize = chunk.count
                    nextPartNumber += 1
                    group.addTask {
                        let etag = try await self.uploadPart(
                            bucket: bucket, key: key, uploadId: uploadId,
                            partNumber: pn, data: chunk, useUnsignedPayload: useUnsigned
                        )
                        return (pn, etag, chunkSize)
                    }
                }

                // As each upload completes, read next chunk and launch new upload
                for try await (pn, etag, chunkSize) in group {
                    try Task.checkCancellation()
                    completedParts.append((partNumber: pn, etag: etag))
                    bytesUploaded += Int64(chunkSize)
                    progress?(bytesUploaded, fileSize)

                    // Read and launch next part if available
                    if let chunk = try fileHandle.read(upToCount: partSize), !chunk.isEmpty {
                        let nextPN = nextPartNumber
                        let nextSize = chunk.count
                        nextPartNumber += 1
                        group.addTask {
                            let etag = try await self.uploadPart(
                                bucket: bucket, key: key, uploadId: uploadId,
                                partNumber: nextPN, data: chunk, useUnsignedPayload: useUnsigned
                            )
                            return (nextPN, etag, nextSize)
                        }
                    }
                }
            }

            // Parts may complete out of order — sort before finalizing
            completedParts.sort { $0.partNumber < $1.partNumber }
            try await completeMultipartUpload(bucket: bucket, key: key, uploadId: uploadId, parts: completedParts)
        } catch {
            try? await abortMultipartUpload(bucket: bucket, key: key, uploadId: uploadId)
            throw error
        }
    }

    /// Routes upload to single PUT or multipart based on file size.
    /// - Small files (< 20 MB): single PUT with in-memory Data
    /// - Large files (>= 20 MB): multipart upload with FileHandle chunking (memory-safe)
    /// Content-MD5 and UNSIGNED-PAYLOAD are applied only for non-local endpoints.
    func uploadObject(
        bucket: String,
        key: String,
        fileURL: URL,
        contentType: String,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws {
        let fileSize = try Int64(fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)

        if fileSize < Self.multipartThreshold {
            // Single PUT — small files are safe to buffer in memory
            let data = try Data(contentsOf: fileURL)
            var headers: [String: String] = [:]
            if !client.isLocalEndpoint {
                headers["Content-MD5"] = SigV4Signer.md5Base64(data)
            }
            _ = try await client.s3Request(
                method: "PUT",
                path: "/\(bucket)/\(key)",
                body: data,
                contentType: contentType,
                headers: headers
            )
        } else {
            // Multipart upload — FileHandle chunking keeps memory at ~partSize
            try await putObjectMultipart(
                bucket: bucket,
                key: key,
                fileURL: fileURL,
                contentType: contentType,
                progress: progress
            )
        }
    }

    func createFolder(bucket: String, prefix: String, name: String) async throws {
        let key = prefix + name + "/"
        _ = try await client.s3Request(
            method: "PUT",
            path: "/\(bucket)/\(key)",
            body: Data(),
            contentType: "application/x-directory"
        )
    }

    func moveObject(bucket: String, sourceKey: String, destinationKey: String) async throws {
        try await serverSideCopy(sourceBucket: bucket, sourceKey: sourceKey, destinationBucket: bucket, destinationKey: destinationKey)
        try await deleteObject(bucket: bucket, key: sourceKey)
    }

    func moveObjects(bucket: String, sourceKeys: [String], destinationPrefix: String) async throws {
        for key in sourceKeys {
            let filename = key.components(separatedBy: "/").last ?? key
            let destinationKey = destinationPrefix + filename
            try await moveObject(bucket: bucket, sourceKey: key, destinationKey: destinationKey)
        }
    }

    /// Recursively moves all objects under `sourcePrefix` to `destinationPrefix`,
    /// preserving relative paths. Returns the number of objects moved.
    @discardableResult
    func moveFolder(bucket: String, sourcePrefix: String, destinationPrefix: String) async throws -> Int {
        let objects = try await listAllObjects(bucket: bucket, prefix: sourcePrefix)
        for obj in objects {
            let relativePath = String(obj.key.dropFirst(sourcePrefix.count))
            let newKey = destinationPrefix + relativePath
            try await moveObject(bucket: bucket, sourceKey: obj.key, destinationKey: newKey)
        }
        return objects.count
    }

    /// Server-side copy between any two buckets (or within the same bucket).
    func serverSideCopy(sourceBucket: String, sourceKey: String, destinationBucket: String, destinationKey: String) async throws {
        let encodedSource = "/\(sourceBucket)/\(sourceKey)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "/\(sourceBucket)/\(sourceKey)"
        _ = try await client.s3Request(
            method: "PUT",
            path: "/\(destinationBucket)/\(destinationKey)",
            headers: ["x-amz-copy-source": encodedSource]
        )
    }

    /// Duplicates an object within the same bucket using server-side copy.
    func duplicateObject(bucket: String, sourceKey: String, destinationKey: String) async throws {
        try await serverSideCopy(sourceBucket: bucket, sourceKey: sourceKey, destinationBucket: bucket, destinationKey: destinationKey)
    }

    /// Duplicates all objects under a prefix to a new prefix using server-side copy.
    @discardableResult
    func duplicateFolder(bucket: String, sourcePrefix: String, destinationPrefix: String) async throws -> Int {
        let objects = try await listAllObjects(bucket: bucket, prefix: sourcePrefix)
        for obj in objects {
            let relativePath = String(obj.key.dropFirst(sourcePrefix.count))
            let newKey = destinationPrefix + relativePath
            try await duplicateObject(bucket: bucket, sourceKey: obj.key, destinationKey: newKey)
        }
        return objects.count
    }

    /// Renames an object within the same bucket using server-side copy + delete.
    func renameObject(bucket: String, sourceKey: String, destinationKey: String) async throws {
        try await serverSideCopy(sourceBucket: bucket, sourceKey: sourceKey, destinationBucket: bucket, destinationKey: destinationKey)
        try await deleteObject(bucket: bucket, key: sourceKey)
    }

    /// Renames a folder by copying all objects to the new prefix, then deleting originals.
    /// Copy-all-then-delete-all is safer: if a copy fails midway, originals remain intact.
    @discardableResult
    func renameFolder(bucket: String, sourcePrefix: String, destinationPrefix: String) async throws -> Int {
        let objects = try await listAllObjects(bucket: bucket, prefix: sourcePrefix)
        for obj in objects {
            let relativePath = String(obj.key.dropFirst(sourcePrefix.count))
            let newKey = destinationPrefix + relativePath
            try await serverSideCopy(sourceBucket: bucket, sourceKey: obj.key, destinationBucket: bucket, destinationKey: newKey)
        }
        for obj in objects {
            try await deleteObject(bucket: bucket, key: obj.key)
        }
        return objects.count
    }

    /// Recursively copies all objects under sourcePrefix to destinationPrefix, preserving relative paths.
    @discardableResult
    func copyFolder(sourceBucket: String, sourcePrefix: String,
                    destinationBucket: String, destinationPrefix: String) async throws -> Int {
        let objects = try await listAllObjects(bucket: sourceBucket, prefix: sourcePrefix)
        for obj in objects {
            let relativePath = String(obj.key.dropFirst(sourcePrefix.count))
            let newKey = destinationPrefix + relativePath
            try await serverSideCopy(sourceBucket: sourceBucket, sourceKey: obj.key,
                                      destinationBucket: destinationBucket, destinationKey: newKey)
        }
        return objects.count
    }

    /// Copies an object within the same bucket or across buckets using server-side copy.
    func copyObject(sourceBucket: String, sourceKey: String, destinationBucket: String, destinationKey: String) async throws {
        try await serverSideCopy(sourceBucket: sourceBucket, sourceKey: sourceKey, destinationBucket: destinationBucket, destinationKey: destinationKey)
    }

    /// Moves an object from one bucket to another using copy + delete.
    func moveObjectToBucket(sourceBucket: String, sourceKey: String, destinationBucket: String, destinationKey: String) async throws {
        try await copyObject(sourceBucket: sourceBucket, sourceKey: sourceKey, destinationBucket: destinationBucket, destinationKey: destinationKey)
        try await deleteObject(bucket: sourceBucket, key: sourceKey)
    }

    /// Recursively moves all objects under `sourcePrefix` to another bucket,
    /// preserving relative paths. Returns the number of objects moved.
    @discardableResult
    func moveFolderToBucket(sourceBucket: String, sourcePrefix: String, destinationBucket: String, destinationPrefix: String) async throws -> Int {
        let objects = try await listAllObjects(bucket: sourceBucket, prefix: sourcePrefix)
        for obj in objects {
            let relativePath = String(obj.key.dropFirst(sourcePrefix.count))
            let newKey = destinationPrefix + relativePath
            try await moveObjectToBucket(sourceBucket: sourceBucket, sourceKey: obj.key, destinationBucket: destinationBucket, destinationKey: newKey)
        }
        return objects.count
    }

    /// Downloads all objects under a prefix into a temp directory and zips them.
    /// Returns the ZIP file URL, or nil if the folder has no downloadable files.
    /// Caller is responsible for cleaning up the returned URL and its parent temp directory.
    func downloadFolderAsZip(
        bucket: String,
        prefix: String,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> URL? {
        let allObjects = try await listAllObjects(bucket: bucket, prefix: prefix)
        // Filter out zero-byte folder markers
        let files = allObjects.filter { !($0.key.hasSuffix("/") && $0.size == 0) }
        guard !files.isEmpty else { return nil }

        let folderName = String(prefix.dropLast()).components(separatedBy: "/").last ?? "folder"
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contentDir = tempBase.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        for (index, obj) in files.enumerated() {
            let relativePath = String(obj.key.dropFirst(prefix.count))
            let fileURL = contentDir.appendingPathComponent(relativePath)
            let parentDir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            try await downloadObjectToFile(bucket: bucket, key: obj.key, destination: fileURL)
            progress(index + 1, files.count)
        }

        let zipURL = tempBase.appendingPathComponent("\(folderName).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", contentDir.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "S3Service", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP archive"])
        }

        // Clean up the unzipped content, keep the zip
        try? FileManager.default.removeItem(at: contentDir)
        return zipURL
    }

    func emptyBucket(bucket: String, progress: ((Int) -> Void)? = nil) async throws {
        let objects = try await listAllObjects(bucket: bucket, prefix: "")
        if !objects.isEmpty {
            _ = try await deleteObjects(bucket: bucket, keys: objects.map(\.key), progress: progress)
        }
    }

    func forceDeleteBucket(bucket: String, progress: ((Int) -> Void)? = nil) async throws {
        try await emptyBucket(bucket: bucket, progress: progress)
        try await deleteBucket(name: bucket)
    }

    func deleteObject(bucket: String, key: String) async throws {
        _ = try await client.s3Request(method: "DELETE", path: "/\(bucket)/\(key)")
    }

    func deleteObjects(bucket: String, keys: [String], progress: ((Int) -> Void)? = nil) async throws -> Int {
        let maxConcurrency = 10
        var deleted = 0

        await withTaskGroup(of: Bool.self) { group in
            for (index, key) in keys.enumerated() {
                if index >= maxConcurrency {
                    // Wait for one to finish before adding more
                    if let success = await group.next(), success {
                        deleted += 1
                        progress?(deleted)
                    }
                }
                group.addTask {
                    do {
                        try await self.deleteObject(bucket: bucket, key: key)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            // Collect remaining results
            for await success in group {
                if success {
                    deleted += 1
                    progress?(deleted)
                }
            }
        }
        return deleted
    }

    func headObject(bucket: String, key: String) async throws -> S3ObjectDetail {
        let headers = try await client.s3Head(path: "/\(bucket)/\(key)")

        var metadata: [String: String] = [:]
        for (k, v) in headers where k.hasPrefix("x-amz-meta-") {
            let metaKey = String(k.dropFirst("x-amz-meta-".count))
            metadata[metaKey] = v
        }

        return S3ObjectDetail(
            key: key,
            size: Int64(headers["content-length"] ?? "0") ?? 0,
            contentType: headers["content-type"] ?? "application/octet-stream",
            lastModified: headers["last-modified"] ?? "",
            etag: headers["etag"] ?? "",
            metadata: metadata
        )
    }

    func getBucketPolicy(bucket: String) async throws -> String {
        let data = try await client.s3Request(method: "GET", path: "/\(bucket)?policy")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func putBucketPolicy(bucket: String, json: String) async throws {
        guard let body = json.data(using: .utf8) else { return }
        _ = try await client.s3Request(
            method: "PUT",
            path: "/\(bucket)?policy",
            body: body,
            contentType: "application/json"
        )
    }
}
