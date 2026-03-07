import SwiftUI

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case limited
    case paid
}

@MainActor
final class LicenseManager: ObservableObject {
    static let trialDuration = 14
    private static let trialStartDateKey = "LicenseManager.trialStartDate"

    @Published private(set) var state: LicenseState = .trial(daysRemaining: trialDuration)
    @Published var showUpgradeSheet = false

    private let storeKit: StoreKitManager
    /// Set by the app so LicenseManager can force read-only in limited mode.
    weak var appState: AppState?

    var isPaid: Bool { state == .paid }

    var canWrite: Bool {
        switch state {
        case .trial, .paid: return true
        case .limited: return false
        }
    }

    var daysRemaining: Int? {
        if case .trial(let days) = state { return days }
        return nil
    }

    init(storeKit: StoreKitManager) {
        self.storeKit = storeKit
        ensureTrialStartDate()
        refreshState()
    }

    func refreshState() {
        if storeKit.isPurchased {
            state = .paid
            // Unlock read-only if it was forced by limited mode
            appState?.isReadOnly = false
            return
        }

        let remaining = Self.computeDaysRemaining()
        if remaining > 0 {
            state = .trial(daysRemaining: remaining)
        } else {
            state = .limited
            // Force read-only in limited mode — all 28 modules already check appState.isReadOnly
            appState?.isReadOnly = true
        }
    }

    /// Call this when the user attempts a write action in limited mode.
    /// Returns `true` if the action is allowed, `false` if blocked (and shows the upgrade sheet).
    func guardWriteAction() -> Bool {
        if canWrite { return true }
        showUpgradeSheet = true
        return false
    }

    // MARK: - Trial Date

    private func ensureTrialStartDate() {
        if UserDefaults.standard.object(forKey: Self.trialStartDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.trialStartDateKey)
            Log.info("Trial started", category: "License")
        }
    }

    private static func computeDaysRemaining() -> Int {
        guard let startDate = UserDefaults.standard.object(forKey: trialStartDateKey) as? Date else {
            return trialDuration
        }
        // Guard against clock manipulation — if "now" is before the start date, use start date
        let now = max(Date(), startDate)
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 0
        return max(0, trialDuration - elapsed)
    }
}
