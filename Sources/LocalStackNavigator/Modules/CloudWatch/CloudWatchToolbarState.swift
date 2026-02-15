import SwiftUI

@MainActor
final class CloudWatchToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case putMetric
        case createAlarm
        case deleteAlarm
        case setAlarmState
    }

    func reset() {
        pendingAction = nil
    }
}

struct CloudWatchToolbar: ToolbarContent {
    @ObservedObject var state: CloudWatchToolbarState
    let isReadOnly: Bool
    let tab: CloudWatchTab
    let hasAlarmSelection: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .putMetric } label: {
                Label("Put Metric", systemImage: "chart.line.uptrend.xyaxis")
                    .toolbarHitTarget()
            }
            .help("Put Metric Data")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createAlarm } label: {
                Label("Create Alarm", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Alarm")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .setAlarmState } label: {
                Label("Set State", systemImage: "flag")
                    .toolbarHitTarget()
            }
            .help("Set Alarm State")
            .disabled(!hasAlarmSelection || isReadOnly || tab != .alarms)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasAlarmSelection || isReadOnly || tab != .alarms
            Button { state.pendingAction = .deleteAlarm } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Alarm")
            .disabled(disabled)
        }
    }
}
