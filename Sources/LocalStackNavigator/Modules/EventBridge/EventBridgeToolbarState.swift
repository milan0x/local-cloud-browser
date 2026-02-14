import SwiftUI

@MainActor
final class EventBridgeToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case putEvent
        case createRule
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct EventBridgeToolbar: ToolbarContent {
    @ObservedObject var state: EventBridgeToolbarState
    let isReadOnly: Bool
    let hasBus: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Event Bus Details")
            .disabled(!hasBus)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .putEvent } label: {
                Label("Put Event", systemImage: "paperplane")
                    .toolbarHitTarget()
            }
            .help("Send Test Event")
            .disabled(!hasBus || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createRule } label: {
                Label("Create Rule", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Rule")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasBus || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Event Bus")
            .disabled(disabled)
        }
    }
}
