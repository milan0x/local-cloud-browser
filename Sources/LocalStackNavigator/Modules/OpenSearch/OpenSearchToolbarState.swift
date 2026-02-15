import SwiftUI

@MainActor
final class OpenSearchToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createDomain
        case deleteDomain
    }

    func reset() {
        pendingAction = nil
    }
}

struct OpenSearchToolbar: ToolbarContent {
    @ObservedObject var state: OpenSearchToolbarState
    let isReadOnly: Bool
    let hasDomain: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createDomain } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Domain")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasDomain || isReadOnly
            Button { state.pendingAction = .deleteDomain } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Domain")
            .disabled(disabled)
        }
    }
}
