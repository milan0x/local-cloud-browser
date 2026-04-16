import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Content MD5")
struct ContentMD5Tests {

    @Test("MD5 of empty data matches known hash")
    func md5Empty() {
        let hash = ContentMD5.md5(Data())
        // MD5 of empty string = d41d8cd98f00b204e9800998ecf8427e
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "d41d8cd98f00b204e9800998ecf8427e")
    }

    @Test("MD5 of known input matches expected hash")
    func md5Known() {
        let data = "hello".data(using: .utf8)!
        let hash = ContentMD5.md5(data)
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        // MD5 of "hello" = 5d41402abc4b2a76b9719d911017c592
        #expect(hex == "5d41402abc4b2a76b9719d911017c592")
    }

    @Test("contentMD5Header returns valid base64")
    func headerFormat() {
        let data = "test".data(using: .utf8)!
        let header = ContentMD5.contentMD5Header(data)
        // Should be valid base64
        #expect(Data(base64Encoded: header) != nil)
    }

    @Test("contentMD5Header is consistent")
    func headerConsistency() {
        let data = "consistent".data(using: .utf8)!
        let a = ContentMD5.contentMD5Header(data)
        let b = ContentMD5.contentMD5Header(data)
        #expect(a == b)
    }
}
