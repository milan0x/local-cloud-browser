import SwiftUI

enum LicenseState: Equatable {
    case free
    case paid
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var state: LicenseState = .free
    @Published var showUpgradeSheet = false

    private let storeKit: StoreKitManager
    /// Set by the app so LicenseManager can force read-only in free mode.
    weak var appState: AppState?

    private static let trialStartKey = "trialStartDate"
    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    var isPaid: Bool { state == .paid }

    var canWrite: Bool { state == .paid }

    /// Days remaining in the trial period, or 0 if expired.
    var trialDaysRemaining: Int {
        guard let start = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date else {
            return 14
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = Self.trialDuration - elapsed
        return max(0, Int(ceil(remaining / (24 * 60 * 60))))
    }

    var isTrialExpired: Bool { trialDaysRemaining <= 0 }

    init(storeKit: StoreKitManager) {
        self.storeKit = storeKit
        ensureTrialStartDate()
        refreshState()
    }

    private func ensureTrialStartDate() {
        if UserDefaults.standard.object(forKey: Self.trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.trialStartKey)
        }
    }

    func refreshState() {
        if storeKit.isPurchased {
            state = .paid
            appState?.isReadOnly = false
        } else {
            state = .free
            appState?.isReadOnly = true
        }
    }

    /// Call this when the user attempts a write action in free mode.
    /// Returns `true` if the action is allowed, `false` if blocked (and shows the upgrade sheet).
    func guardWriteAction() -> Bool {
        if canWrite { return true }
        showUpgradeSheet = true
        return false
    }
}
