import SwiftUI

@MainActor
final class Route53ToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createZone
        case createRecord
        case deleteZone
        case createEndpoint
        case createRule
        case deleteEndpoint
    }

    func reset() {
        pendingAction = nil
    }
}

struct Route53Toolbar: ToolbarContent {
    @ObservedObject var state: Route53ToolbarState
    let isReadOnly: Bool
    let tab: Route53Tab
    let hasZone: Bool
    let hasEndpoint: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.pendingAction = tab == .zones ? .createZone : .createEndpoint
            } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help(tab == .zones ? "Create Hosted Zone" : "Create Resolver Endpoint")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.pendingAction = tab == .zones ? .createRecord : .createRule
            } label: {
                Label(
                    tab == .zones ? "Create Record" : "Create Rule",
                    systemImage: "text.badge.plus"
                )
                .toolbarHitTarget()
            }
            .help(tab == .zones ? "Create Record Set" : "Create Resolver Rule")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let hasSelection = tab == .zones ? hasZone : hasEndpoint
            let disabled = !hasSelection || isReadOnly
            Button {
                state.pendingAction = tab == .zones ? .deleteZone : .deleteEndpoint
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help(tab == .zones ? "Delete Hosted Zone" : "Delete Resolver Endpoint")
            .disabled(disabled)
        }
    }
}
