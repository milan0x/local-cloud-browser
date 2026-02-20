import Testing
@testable import LocalCloudBrowser

@Suite("ReadOnlyInterceptor")
struct ReadOnlyInterceptorTests {

    // MARK: - Read-only ON

    @Test("GET allowed in read-only mode")
    func getReadOnly() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "GET", isReadOnly: true))
    }

    @Test("HEAD allowed in read-only mode")
    func headReadOnly() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "HEAD", isReadOnly: true))
    }

    @Test("OPTIONS allowed in read-only mode")
    func optionsReadOnly() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "OPTIONS", isReadOnly: true))
    }

    @Test("POST blocked in read-only mode")
    func postReadOnly() {
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "POST", isReadOnly: true))
    }

    @Test("PUT blocked in read-only mode")
    func putReadOnly() {
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "PUT", isReadOnly: true))
    }

    @Test("DELETE blocked in read-only mode")
    func deleteReadOnly() {
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "DELETE", isReadOnly: true))
    }

    @Test("PATCH blocked in read-only mode")
    func patchReadOnly() {
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "PATCH", isReadOnly: true))
    }

    @Test("Case insensitive blocking")
    func caseInsensitive() {
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "post", isReadOnly: true))
        #expect(!ReadOnlyInterceptor.allowsRequest(method: "Post", isReadOnly: true))
    }

    // MARK: - Read-only OFF

    @Test("POST allowed when read-only is off")
    func postAllowed() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "POST", isReadOnly: false))
    }

    @Test("DELETE allowed when read-only is off")
    func deleteAllowed() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "DELETE", isReadOnly: false))
    }

    @Test("PUT allowed when read-only is off")
    func putAllowed() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "PUT", isReadOnly: false))
    }

    @Test("PATCH allowed when read-only is off")
    func patchAllowed() {
        #expect(ReadOnlyInterceptor.allowsRequest(method: "PATCH", isReadOnly: false))
    }
}
