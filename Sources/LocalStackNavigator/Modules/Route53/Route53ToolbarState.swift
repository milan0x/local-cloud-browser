import SwiftUI

@MainActor
final class Route53ToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createZone
        case createRecord
        case deleteZone
    }

    func reset() {
        pendingAction = nil
    }
}

struct Route53Toolbar: ToolbarContent {
    @ObservedObject var state: Route53ToolbarState
    let isReadOnly: Bool
    let hasZone: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createZone } label: {
                Label("Create Zone", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Hosted Zone")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createRecord } label: {
                Label("Create Record", systemImage: "text.badge.plus")
                    .toolbarHitTarget()
            }
            .help("Create Record Set")
            .disabled(!hasZone || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasZone || isReadOnly
            Button { state.pendingAction = .deleteZone } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Hosted Zone")
            .disabled(disabled)
        }
    }
}
