import SwiftUI

@MainActor
final class ResourceGroupsToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createGroup
        case deleteGroup
    }

    func reset() {
        pendingAction = nil
    }
}

struct ResourceGroupsToolbar: ToolbarContent {
    @ObservedObject var state: ResourceGroupsToolbarState
    let isReadOnly: Bool
    let hasGroup: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createGroup } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Resource Group")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasGroup || isReadOnly
            Button { state.pendingAction = .deleteGroup } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Resource Group")
            .disabled(disabled)
        }
    }
}
