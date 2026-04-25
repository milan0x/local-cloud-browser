import Foundation

// MARK: - Byte Accumulator

/// Thread-safe accumulator for tracking cumulative bytes across concurrent uploads.
/// `nonisolated` on `add` so the @Sendable progress callback in
/// uploadMultipart can call it without an actor-isolation violation —
/// the NSLock makes it safe.
private final class ByteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    // `nonisolated(unsafe)` because mutation is guarded by NSLock — the
    // class is `@unchecked Sendable` for the same reason.
    nonisolated(unsafe) private var total: Int64 = 0

    nonisolated func add(_ bytes: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        total += bytes
        return total
    }
}

// MARK: - Streaming Upload Errors

enum StreamingUploadError: Error, LocalizedError {
    case fileTooLarge
    case missingUploadId
    case missingETag(partNumber: Int)
    case partUploadFailed(partNumber: Int, underlying: Error)
    case completionFailed(underlying: Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "File exceeds maximum upload size"
        case .missingUploadId: "Server did not return an upload ID"
        case .missingETag(let n): "Server did not return ETag for part \(n)"
        case .partUploadFailed(let n, let e): "Part \(n) upload failed: \(e.localizedDescription)"
        case .completionFailed(let e): "Failed to complete multipart upload: \(e.localizedDescription)"
        case .cancelled: "Upload was cancelled"
        }
    }
}

// MARK: - Upload Progress Delegate

/// URLSession delegate that forwards body-send progress to a closure.
/// Used to get smooth, byte-by-byte progress updates during S3 uploads —
/// without it, `URLSession.upload(for:fromFile:)` only "reports" progress
/// once the whole upload finishes, giving the user a sudden 0% → 100% jump.
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onSent: @Sendable (Int64) -> Void

    init(onSent: @escaping @Sendable (Int64) -> Void) {
        self.onSent = onSent
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        // `bytesSent` is the delta for THIS callback (not cumulative). Caller
        // accumulates if it needs cumulative bytes.
        onSent(bytesSent)
    }
}

// MARK: - Streaming Uploader

final class StreamingUploader: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Uploads a file using single PUT (for files <= 5MB).
    func uploadSingleFile(
        fileURL: URL,
        signingContext: RequestSigningContext,
        bucket: String,
        key: String,
        contentType: String,
        progress: @Sendable @escaping (Int64) -> Void
    ) async throws {
        let fileSize = try fileURL.fileSize()

        // Use UNSIGNED-PAYLOAD so we don't need the file in memory for signing
        var request = try signingContext.signedS3Request(
            method: "PUT",
            path: "/\(bucket)/\(key)",
            contentType: contentType,
            payloadHash: "UNSIGNED-PAYLOAD"
        )
        request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")

        // Delegate captures `didSendBodyData` so progress ticks smoothly as
        // bytes go on the wire — without this, single-PUT files jumped
        // from 0% straight to 100%. Delegate emits deltas; we accumulate
        // here to give the caller cumulative-bytes-sent for this file.
        let counter = ByteAccumulator()
        let delegate = UploadProgressDelegate { delta in
            let cumulative = counter.add(delta)
            progress(cumulative)
        }
        let (_, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudClientError.httpError(statusCode: statusCode, data: Data())
        }
        // Final clamp to 100% in case the last delegate callback came in
        // marginally before the response — guarantees the UI lands on done.
        progress(fileSize)
    }

    /// Uploads a file using S3 multipart upload (for files > 5MB).
    func uploadMultipart(
        fileURL: URL,
        signingContext: RequestSigningContext,
        bucket: String,
        key: String,
        contentType: String,
        plan: MultipartUploadPlan,
        progress: @Sendable @escaping (Int64) -> Void
    ) async throws {
        // Step 1: Initiate multipart upload
        let initiateRequest = try signingContext.signedS3Request(
            method: "POST",
            path: "/\(bucket)/\(key)",
            queryParams: ["uploads": ""],
            contentType: contentType
        )

        let (initiateData, initiateResponse) = try await session.data(for: initiateRequest)
        guard let initiateHttp = initiateResponse as? HTTPURLResponse,
              (200..<300).contains(initiateHttp.statusCode) else {
            let sc = (initiateResponse as? HTTPURLResponse)?.statusCode ?? 0
            throw CloudClientError.httpError(statusCode: sc, data: initiateData)
        }

        let uploadId = try S3InitiateMultipartUploadParser().parse(data: initiateData)

        // Wrap everything from this point in a do-catch so we can AWAIT the
        // abort call on any failure path (cancellation, part failure, complete
        // failure). The previous `defer { Task { ... } }` launched a detached
        // Task that was not awaited — if the enclosing Task was cancelled or
        // the process exited, the abort often never ran and the parts would
        // accumulate in the bucket, costing real money on AWS.
        do {
            // Step 2: Upload parts with limited concurrency
            let accumulator = ByteAccumulator()
            let cumulativeProgress: @Sendable (Int64) -> Void = { chunkBytes in
                let total = accumulator.add(chunkBytes)
                progress(total)
            }
            let maxConcurrency = 4
            let completedParts = try await uploadParts(
                fileURL: fileURL,
                bucket: bucket,
                key: key,
                uploadId: uploadId,
                plan: plan,
                signingContext: signingContext,
                maxConcurrency: maxConcurrency,
                progress: cumulativeProgress
            )

            // Step 3: Complete multipart upload
            try Task.checkCancellation()
            let xmlBody = MultipartUploadPlan.completeMultipartXML(parts: completedParts)
            let completeRequest = try signingContext.signedS3Request(
                method: "POST",
                path: "/\(bucket)/\(key)",
                queryParams: ["uploadId": uploadId],
                body: xmlBody,
                contentType: "application/xml"
            )

            let (completeData, completeResponse) = try await session.data(for: completeRequest)
            guard let completeHttp = completeResponse as? HTTPURLResponse,
                  (200..<300).contains(completeHttp.statusCode) else {
                let sc = (completeResponse as? HTTPURLResponse)?.statusCode ?? 0
                throw StreamingUploadError.completionFailed(
                    underlying: CloudClientError.httpError(statusCode: sc, data: completeData)
                )
            }

            Log.info("Completed multipart upload \(uploadId) for \(key)", category: "Upload")
        } catch {
            // Await the abort so the multipart upload is cleaned up before we
            // re-throw. Best-effort — if the abort itself fails (e.g. network
            // already down), we still re-throw the original error. Using
            // `Task { ... }.value` decouples from any cancellation of the
            // parent Task so an ongoing cancel doesn't short-circuit the abort.
            await Task { [session, signingContext] in
                guard let abortReq = try? signingContext.signedS3Request(
                    method: "DELETE",
                    path: "/\(bucket)/\(key)",
                    queryParams: ["uploadId": uploadId]
                ) else { return }
                _ = try? await session.data(for: abortReq)
                Log.info("Aborted multipart upload \(uploadId) after error: \(error)", category: "Upload")
            }.value
            throw error
        }
    }

    // MARK: - Private

    private func uploadParts(
        fileURL: URL,
        bucket: String,
        key: String,
        uploadId: String,
        plan: MultipartUploadPlan,
        signingContext: RequestSigningContext,
        maxConcurrency: Int,
        progress: @Sendable @escaping (Int64) -> Void
    ) async throws -> [CompletedPart] {
        try await withThrowingTaskGroup(of: CompletedPart.self) { group in
            var completedParts: [CompletedPart] = []
            var partIndex = 0

            func addNextPart() throws {
                guard partIndex < plan.parts.count else { return }
                let part = plan.parts[partIndex]
                partIndex += 1

                group.addTask { [session] in
                    try Task.checkCancellation()

                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: UInt64(part.offset))
                    guard let chunkData = try handle.read(upToCount: part.length), !chunkData.isEmpty else {
                        throw StreamingUploadError.partUploadFailed(
                            partNumber: part.partNumber,
                            underlying: NSError(domain: "StreamingUploader", code: 1,
                                                userInfo: [NSLocalizedDescriptionKey: "Failed to read file chunk"])
                        )
                    }

                    let md5Header = ContentMD5.contentMD5Header(chunkData)

                    let request = try signingContext.signedS3Request(
                        method: "PUT",
                        path: "/\(bucket)/\(key)",
                        queryParams: [
                            "partNumber": "\(part.partNumber)",
                            "uploadId": uploadId,
                        ],
                        body: chunkData,
                        contentType: "application/octet-stream",
                        extraHeaders: ["Content-MD5": md5Header]
                    )

                    // Delegate streams per-byte deltas as the chunk uploads.
                    // The outer accumulator (in uploadMultipart) sums them
                    // across concurrent parts. Without this, multipart progress
                    // only ticked once per part (every ~10 MB).
                    let delegate = UploadProgressDelegate(onSent: progress)
                    let (_, response) = try await session.upload(for: request, from: chunkData, delegate: delegate)
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode) else {
                        let sc = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw StreamingUploadError.partUploadFailed(
                            partNumber: part.partNumber,
                            underlying: CloudClientError.httpError(statusCode: sc, data: Data())
                        )
                    }

                    guard let etag = http.value(forHTTPHeaderField: "ETag") else {
                        throw StreamingUploadError.missingETag(partNumber: part.partNumber)
                    }

                    // (No final progress(chunkData.count) — the delegate
                    // already streamed the per-byte deltas. Adding a final
                    // bump would double-count and overshoot 100%.)
                    return CompletedPart(partNumber: part.partNumber, etag: etag)
                }
            }

            // Seed initial concurrent tasks
            for _ in 0..<min(maxConcurrency, plan.parts.count) {
                try addNextPart()
            }

            // Process results and add more parts
            for try await completedPart in group {
                completedParts.append(completedPart)
                try addNextPart()
            }

            return completedParts
        }
    }
}

// MARK: - File URL Extension

private extension URL {
    func fileSize() throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return attrs[.size] as? Int64 ?? 0
    }
}
