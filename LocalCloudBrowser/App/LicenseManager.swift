import SwiftUI

enum LicenseState: Equatable {
    case free
    case paid
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var state: LicenseState = .free
    @Published var showUpgradeSheet = false
    @Published var upgradeContext: String?

    private let storeKit: StoreKitManager
    weak var appState: AppState?

    static let freeCreateLimit = 3

    var isPaid: Bool { state == .paid }

    init(storeKit: StoreKitManager) {
        self.storeKit = storeKit
        // Clean up legacy trial key from older versions
        UserDefaults.standard.removeObject(forKey: "trialStartDate")
        refreshState()
    }

    func refreshState() {
        if storeKit.isPurchased {
            state = .paid
            appState?.isReadOnly = false
        } else {
            state = .free
        }
    }

    // MARK: - Per-Service Create Quota

    func createCount(for service: Route) -> Int {
        UserDefaults.standard.integer(forKey: "freeCreates_\(service.rawValue)")
    }

    func remainingCreates(for service: Route) -> Int {
        max(0, Self.freeCreateLimit - createCount(for: service))
    }

    func incrementCreateCount(for service: Route) {
        guard !isPaid else { return }
        let key = "freeCreates_\(service.rawValue)"
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    /// Call when the user attempts to create a resource.
    /// Returns `true` if the action is allowed, `false` if blocked (shows upgrade sheet).
    func guardWriteAction(for service: Route?) -> Bool {
        if isPaid { return true }
        guard let service else { return true }
        if remainingCreates(for: service) > 0 { return true }
        let used = createCount(for: service)
        upgradeContext = "You've created \(used)/\(Self.freeCreateLimit) \(service.displayName) resources. Upgrade for unlimited."
        showUpgradeSheet = true
        return false
    }
}
