import Foundation
import Testing
@testable import LocalCloudBrowser

// MARK: - LicenseState

@Suite("LicenseState")
struct LicenseStateTests {
    @Test("free state properties")
    func freeState() {
        let state = LicenseState.free
        #expect(state == .free)
        #expect(state != .paid)
    }

    @Test("paid state properties")
    func paidState() {
        let state = LicenseState.paid
        #expect(state != .free)
        #expect(state == .paid)
    }
}
