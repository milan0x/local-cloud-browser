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

    var isPaid: Bool { state == .paid }

    var canWrite: Bool { state == .paid }

    init(storeKit: StoreKitManager) {
        self.storeKit = storeKit
        refreshState()
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
