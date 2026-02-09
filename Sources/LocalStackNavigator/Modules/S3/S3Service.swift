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

    func deleteObject(bucket: String, key: String) async throws {
        _ = try await client.s3Request(method: "DELETE", path: "/\(bucket)/\(key)")
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
