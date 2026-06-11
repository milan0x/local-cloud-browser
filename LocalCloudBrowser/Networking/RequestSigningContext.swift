import Foundation

/// Sendable snapshot of credentials and endpoint for background signing.
/// Captured from CloudClient/AppState on the main thread, then used
/// by StreamingUploader on background threads without @MainActor access.
struct RequestSigningContext: Sendable {
    let endpoint: String
    let s3BaseURL: String
    let region: String
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    let needsSigning: Bool
    let isReadOnly: Bool
    let usesVirtualHostedStyle: Bool

    /// Rewrites path-style `/bucket/key` to virtual-hosted-style for AWS.
    nonisolated private func resolveURL(for path: String) -> (base: String, path: String) {
        guard usesVirtualHostedStyle else { return (s3BaseURL, path) }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        guard let bucket = parts.first else { return (s3BaseURL, path) }
        let remainingPath = parts.count > 1 ? "/\(parts[1])" : "/"
        guard var components = URLComponents(string: endpoint) else { return (s3BaseURL, path) }
        components.host = "\(bucket).\(components.host ?? "")"
        return (components.string ?? s3BaseURL, remainingPath)
    }

    nonisolated func signedS3Request(
        method: String,
        path: String,
        queryParams: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil,
        payloadHash: String? = nil,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        // Enforce read-only here, not just in the view layer — this is the
        // only chokepoint for the streaming upload path, which bypasses
        // CloudClient.executeRequest and its ReadOnlyInterceptor check.
        guard ReadOnlyInterceptor.allowsRequest(method: method, isReadOnly: isReadOnly) else {
            throw CloudClientError.readOnlyBlocked(method: method)
        }

        let (effectiveBase, effectivePath) = resolveURL(for: path)

        // Encode each path segment with the same charset SigV4 uses (RFC 3986 unreserved + '/')
        var s3PathAllowed = CharacterSet.alphanumerics
        s3PathAllowed.insert(charactersIn: "-._~")
        let encodedPath = effectivePath.components(separatedBy: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: s3PathAllowed) ?? $0 }
            .joined(separator: "/")

        guard var components = URLComponents(string: effectiveBase + encodedPath) else {
            throw URLError(.badURL)
        }
        if !queryParams.isEmpty {
            // Same RFC 3986 encoding the SigV4 canonical query uses — a
            // literal '+' on the wire is decoded as a space by S3 but signed
            // as %2B, breaking the signature (see buildURLRequest).
            components.percentEncodedQueryItems = queryParams.map {
                URLQueryItem(
                    name: SigV4Signer.uriEncode($0.key, encodeSlash: true),
                    value: SigV4Signer.uriEncode($0.value, encodeSlash: true)
                )
            }
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if needsSigning {
            let useUnsignedPayload = payloadHash == "UNSIGNED-PAYLOAD"
            SigV4Signer.sign(
                request: &request,
                body: useUnsignedPayload ? nil : body,
                region: region,
                service: "s3",
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken.isEmpty ? nil : sessionToken,
                unsignedPayload: useUnsignedPayload
            )
        }

        return request
    }
}
