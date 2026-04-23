import Foundation
import CommonCrypto
import CryptoKit

enum SigV4Signer {
    static func sign(
        request: inout URLRequest,
        body: Data?,
        region: String,
        service: String,
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        unsignedPayload: Bool = false,
        date: Date = Date()
    ) {
        let payloadHash: String
        if unsignedPayload {
            payloadHash = "UNSIGNED-PAYLOAD"
        } else {
            let bodyData = body ?? Data()
            payloadHash = hexEncode(sha256(bodyData))
        }

        // Timestamps
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let amzDate = dateFormatter.string(from: date)

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "yyyyMMdd"
        shortDateFormatter.timeZone = TimeZone(identifier: "UTC")
        shortDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let shortDate = shortDateFormatter.string(from: date)

        // Set required headers
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        // Session token must be set before canonical request computation
        // so it's included in signed headers.
        if let sessionToken, !sessionToken.isEmpty {
            request.setValue(sessionToken, forHTTPHeaderField: "x-amz-security-token")
        }

        // Host header (include port if non-standard)
        if let url = request.url, let host = url.host {
            let port = url.port
            let isStandardPort = port == nil || port == 80 || port == 443
            let hostHeader = isStandardPort ? host : "\(host):\(port ?? 0)"
            request.setValue(hostHeader, forHTTPHeaderField: "Host")
        }

        // Canonical request
        let method = request.httpMethod ?? "GET"
        let url = request.url!
        // url.path strips trailing slashes on macOS and decodes percent-
        // encoded characters — both break SigV4 when the key ends in `/`
        // or contains characters like ` `, `+`, or non-ASCII. Extract the
        // exact percent-encoded path from absoluteString, decode it once,
        // then re-encode with SigV4's RFC 3986 unreserved rules so the
        // canonical URI matches the wire URL byte-for-byte.
        let rawPath: String = {
            let abs = url.absoluteString
            guard let hostRange = abs.range(of: "//") else { return url.path }
            let afterScheme = abs[hostRange.upperBound...]
            guard let pathStart = afterScheme.firstIndex(of: "/") else { return "/" }
            let pathAndQuery = abs[pathStart...]
            if let queryStart = pathAndQuery.firstIndex(of: "?") {
                return String(pathAndQuery[..<queryStart])
            }
            return String(pathAndQuery)
        }()
        let decodedPath = (rawPath.isEmpty ? "/" : rawPath).removingPercentEncoding ?? rawPath
        let canonicalURI = uriEncode(decodedPath, encodeSlash: false)
        let canonicalQueryString = canonicalQueryString(from: url)

        // Signed headers — sorted lowercase header names
        let allHeaders = request.allHTTPHeaderFields ?? [:]
        let signedHeaderKeys = allHeaders.keys
            .map { $0.lowercased() }
            .sorted()
        let signedHeaders = signedHeaderKeys.joined(separator: ";")

        let canonicalHeaders = signedHeaderKeys
            .map { key in
                let value = allHeaders.first(where: { $0.key.lowercased() == key })?.value ?? ""
                return "\(key):\(value.trimmingCharacters(in: .whitespaces))\n"
            }
            .joined()

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        // String to sign
        let scope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            hexEncode(sha256(Data(canonicalRequest.utf8))),
        ].joined(separator: "\n")

        // Signing key
        let signingKey = deriveSigningKey(
            secretAccessKey: secretAccessKey,
            date: shortDate,
            region: region,
            service: service
        )

        // Signature
        let signature = hexEncode(hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)))

        // Authorization header
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Crypto helpers

    static func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress, key.count,
                    dataBuffer.baseAddress, data.count,
                    &hash
                )
            }
        }
        return Data(hash)
    }

    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func uriEncode(_ input: String, encodeSlash: Bool) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        if !encodeSlash {
            allowed.insert(charactersIn: "/")
        }
        return input.addingPercentEncoding(withAllowedCharacters: allowed) ?? input
    }

    // MARK: - Internal helpers

    static func deriveSigningKey(
        secretAccessKey: String,
        date: String,
        region: String,
        service: String
    ) -> Data {
        let kSecret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(date.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    /// Computes base64-encoded MD5 hash for Content-MD5 header.
    static func md5Base64(_ data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    static func canonicalQueryString(from url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return ""
        }
        return queryItems
            .map { item in
                let key = uriEncode(item.name, encodeSlash: true)
                let value = uriEncode(item.value ?? "", encodeSlash: true)
                return "\(key)=\(value)"
            }
            .sorted()
            .joined(separator: "&")
    }
}
