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

    @Test("Private IP 192.168.x.x is local")
    func privateIP192() {
        #expect(SafetyGuard.evaluate(endpoint: "http://192.168.1.100:4566") == .local)
    }

    @Test("Private IP 10.x.x.x is local")
    func privateIP10() {
        #expect(SafetyGuard.evaluate(endpoint: "http://10.0.0.5:9000") == .local)
    }

    @Test("Private IP 172.16-31.x.x is local")
    func privateIP172() {
        #expect(SafetyGuard.evaluate(endpoint: "http://172.16.0.1:4566") == .local)
        #expect(SafetyGuard.evaluate(endpoint: "http://172.31.255.255:4566") == .local)
        #expect(SafetyGuard.evaluate(endpoint: "http://172.15.0.1:4566") == .cautionNonLocal)
        #expect(SafetyGuard.evaluate(endpoint: "http://172.32.0.1:4566") == .cautionNonLocal)
    }

    @Test("Link-local 169.254.x.x is local")
    func linkLocal() {
        #expect(SafetyGuard.evaluate(endpoint: "http://169.254.1.1:4566") == .local)
    }

    @Test("Public IP is non-local")
    func publicIP() {
        #expect(SafetyGuard.evaluate(endpoint: "http://8.8.8.8:4566") == .cautionNonLocal)
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
