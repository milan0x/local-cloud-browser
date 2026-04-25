import Foundation
import CryptoKit

enum ContentMD5 {
    /// Computes the MD5 hash of the given data.
    /// MD5 is required by S3 for Content-MD5 headers (not used for security).
    nonisolated static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    /// Returns the base64-encoded MD5 hash suitable for the Content-MD5 HTTP header.
    nonisolated static func contentMD5Header(_ data: Data) -> String {
        md5(data).base64EncodedString()
    }
}
