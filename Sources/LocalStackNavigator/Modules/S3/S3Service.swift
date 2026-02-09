import Foundation

@MainActor
final class S3Service: ObservableObject {
    private var client: LocalStackClient

    init(client: LocalStackClient) {
        self.client = client
    }

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    func listBuckets() async throws -> [S3Bucket] {
        let data = try await client.s3Request(method: "GET", path: "/")
        return try S3BucketListParser().parse(data: data)
    }

    func createBucket(name: String) async throws {
        _ = try await client.s3Request(method: "PUT", path: "/\(name)")
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
        } while token != nil
        return allObjects
    }

    func getObject(bucket: String, key: String) async throws -> Data {
        try await client.s3Request(method: "GET", path: "/\(bucket)/\(key)")
    }

    func putObject(bucket: String, key: String, data: Data, contentType: String) async throws {
        _ = try await client.s3Request(
            method: "PUT",
            path: "/\(bucket)/\(key)",
            body: data,
            contentType: contentType
        )
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
        let detail = try await headObject(bucket: bucket, key: sourceKey)
        let data = try await getObject(bucket: bucket, key: sourceKey)
        try await putObject(bucket: bucket, key: destinationKey, data: data, contentType: detail.contentType)
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

    /// Copies an object within the same bucket or across buckets using GET + PUT.
    func copyObject(sourceBucket: String, sourceKey: String, destinationBucket: String, destinationKey: String) async throws {
        let detail = try await headObject(bucket: sourceBucket, key: sourceKey)
        let data = try await getObject(bucket: sourceBucket, key: sourceKey)
        try await putObject(bucket: destinationBucket, key: destinationKey, data: data, contentType: detail.contentType)
    }

    func deleteObject(bucket: String, key: String) async throws {
        _ = try await client.s3Request(method: "DELETE", path: "/\(bucket)/\(key)")
    }

    func deleteObjects(bucket: String, keys: [String]) async throws -> Int {
        var deleted = 0
        for key in keys {
            try await deleteObject(bucket: bucket, key: key)
            deleted += 1
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
