import Testing
@testable import LocalCloudBrowser

@Suite("SafetyGuard")
struct SafetyGuardTests {

    @Test("localhost is local")
    func localhost() {
        #expect(SafetyGuard.evaluate(endpoint: "http://localhost:4566") == .local)
    }

    @Test("127.0.0.1 is local")
    func loopback() {
        #expect(SafetyGuard.evaluate(endpoint: "http://127.0.0.1:4566") == .local)
    }

    @Test("::1 is local")
    func ipv6Loopback() {
        #expect(SafetyGuard.evaluate(endpoint: "http://[::1]:4566") == .local)
    }

    @Test(".local suffix is local")
    func localSuffix() {
        #expect(SafetyGuard.evaluate(endpoint: "http://myhost.local:4566") == .local)
    }

    @Test("HTTPS localhost is local")
    func httpsLocalhost() {
        #expect(SafetyGuard.evaluate(endpoint: "https://localhost:4566") == .local)
    }

    @Test("Remote host is non-local")
    func remoteHost() {
        #expect(SafetyGuard.evaluate(endpoint: "http://aws.amazon.com:4566") == .cautionNonLocal)
    }

    @Test("IP address that is not loopback is non-local")
    func remoteIP() {
        #expect(SafetyGuard.evaluate(endpoint: "http://192.168.1.100:4566") == .cautionNonLocal)
    }

    @Test("Unparseable endpoint is non-local")
    func unparseable() {
        #expect(SafetyGuard.evaluate(endpoint: "not a url") == .cautionNonLocal)
    }

    @Test("Empty endpoint is non-local")
    func empty() {
        #expect(SafetyGuard.evaluate(endpoint: "") == .cautionNonLocal)
    }

    @Test("Localhost without port is local")
    func localhostNoPort() {
        #expect(SafetyGuard.evaluate(endpoint: "http://localhost") == .local)
    }

    @Test("Case insensitive localhost")
    func caseInsensitive() {
        #expect(SafetyGuard.evaluate(endpoint: "http://LOCALHOST:4566") == .local)
    }
}
