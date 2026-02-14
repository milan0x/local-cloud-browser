import SwiftUI

@MainActor
final class SSMToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case createParameter
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct SSMToolbar: ToolbarContent {
    @ObservedObject var state: SSMToolbarState
    let isReadOnly: Bool
    let hasParameter: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Parameter Details")
            .disabled(!hasParameter)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createParameter } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Parameter")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasParameter || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Parameter")
            .disabled(disabled)
        }
    }
}
