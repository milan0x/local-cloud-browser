import SwiftUI

@MainActor
final class CloudWatchLogsToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case search
        case createLogGroup
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct CloudWatchLogsToolbar: ToolbarContent {
    @ObservedObject var state: CloudWatchLogsToolbarState
    let isReadOnly: Bool
    let hasLogGroup: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Log Group Details")
            .disabled(!hasLogGroup)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .search } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .toolbarHitTarget()
            }
            .help("Search Log Events")
            .disabled(!hasLogGroup)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createLogGroup } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Log Group")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasLogGroup || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Log Group")
            .disabled(disabled)
        }
    }
}
