import SwiftUI

@MainActor
final class IAMToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createEntity
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct IAMToolbar: ToolbarContent {
    @ObservedObject var state: IAMToolbarState
    let isReadOnly: Bool
    let hasSelection: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createEntity } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasSelection || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete")
            .disabled(disabled)
        }
    }
}
