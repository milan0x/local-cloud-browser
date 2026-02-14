import SwiftUI

@MainActor
final class LambdaToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case invoke
        case createFunction
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct LambdaToolbar: ToolbarContent {
    @ObservedObject var state: LambdaToolbarState
    let isReadOnly: Bool
    let hasFunction: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Function Details")
            .disabled(!hasFunction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .invoke } label: {
                Label("Invoke", systemImage: "play")
                    .toolbarHitTarget()
            }
            .help("Invoke Function")
            .disabled(!hasFunction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createFunction } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Function")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasFunction || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Function")
            .disabled(disabled)
        }
    }
}
