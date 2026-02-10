import Foundation

@MainActor
final class AutoRefreshManager: ObservableObject {
    @Published var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: "autoRefreshInterval")
            if interval != oldValue { resetCountdown() }
        }
    }
    @Published private(set) var countdownRemaining: Int = 0
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastRefreshFailed = false
    /// Incremented each time the countdown reaches 0 — views observe this to trigger refresh.
    @Published private(set) var refreshTrigger = 0

    var isActive: Bool { interval > 0 }

    private var timerTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.integer(forKey: "autoRefreshInterval")
        self.interval = stored
        self.countdownRemaining = stored
        startTimer()
    }

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isActive, countdownRemaining > 0 else { return }
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            refreshTrigger += 1
            countdownRemaining = interval
        }
    }

    func reportSuccess() {
        lastSuccessfulRefresh = Date()
        lastRefreshFailed = false
    }

    func reportFailure() {
        lastRefreshFailed = true
    }

    func resetCountdown() {
        countdownRemaining = interval
    }

    func resetState() {
        countdownRemaining = interval
        lastSuccessfulRefresh = nil
        lastRefreshFailed = false
    }
}
