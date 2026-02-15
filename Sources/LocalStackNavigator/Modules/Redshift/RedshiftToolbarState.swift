import SwiftUI

@MainActor
final class RedshiftToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createCluster
        case deleteCluster
    }

    func reset() {
        pendingAction = nil
    }
}

struct RedshiftToolbar: ToolbarContent {
    @ObservedObject var state: RedshiftToolbarState
    let isReadOnly: Bool
    let hasCluster: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createCluster } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Cluster")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasCluster || isReadOnly
            Button { state.pendingAction = .deleteCluster } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Cluster")
            .disabled(disabled)
        }
    }
}
