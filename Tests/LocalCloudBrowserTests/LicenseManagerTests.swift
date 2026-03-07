import Foundation
import Testing
@testable import LocalCloudBrowser

// MARK: - LicenseState

@Suite("LicenseState")
struct LicenseStateTests {
    @Test("trial state properties")
    func trialState() {
        let state = LicenseState.trial(daysRemaining: 10)
        #expect(state == .trial(daysRemaining: 10))
        #expect(state != .limited)
        #expect(state != .paid)
    }

    @Test("limited state properties")
    func limitedState() {
        let state = LicenseState.limited
        #expect(state != .trial(daysRemaining: 0))
        #expect(state == .limited)
        #expect(state != .paid)
    }

    @Test("paid state properties")
    func paidState() {
        let state = LicenseState.paid
        #expect(state != .trial(daysRemaining: 14))
        #expect(state != .limited)
        #expect(state == .paid)
    }
}

// MARK: - Days Remaining Computation

@Suite("License Days Remaining")
struct LicenseDaysRemainingTests {
    @Test("full trial on day zero")
    func dayZero() {
        let start = Date()
        let remaining = LicenseManager.daysRemaining(from: start, to: start)
        #expect(remaining == 14)
    }

    @Test("one day elapsed")
    func oneDayElapsed() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now)
        #expect(remaining == 13)
    }

    @Test("half trial elapsed")
    func halfTrialElapsed() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now)
        #expect(remaining == 7)
    }

    @Test("last day of trial")
    func lastDay() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 13, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now)
        #expect(remaining == 1)
    }

    @Test("trial expired exactly")
    func trialExpiredExactly() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 14, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now)
        #expect(remaining == 0)
    }

    @Test("trial expired long ago")
    func trialExpiredLongAgo() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 100, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now)
        #expect(remaining == 0)
    }

    @Test("clock set backwards does not extend trial")
    func clockManipulation() {
        let start = Date()
        let past = Calendar.current.date(byAdding: .day, value: -5, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: past)
        // Should not go above trial duration — clock backwards treated as day 0
        #expect(remaining == 14)
    }

    @Test("custom trial duration")
    func customDuration() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 3, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now, trialDuration: 7)
        #expect(remaining == 4)
    }

    @Test("custom duration expired")
    func customDurationExpired() {
        let start = Date()
        let now = Calendar.current.date(byAdding: .day, value: 10, to: start)!
        let remaining = LicenseManager.daysRemaining(from: start, to: now, trialDuration: 7)
        #expect(remaining == 0)
    }
}
