import SwiftUI

@MainActor
final class SecretsManagerToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case createSecret
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct SecretsManagerToolbar: ToolbarContent {
    @ObservedObject var state: SecretsManagerToolbarState
    let isReadOnly: Bool
    let hasSecret: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Secret Details")
            .disabled(!hasSecret)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createSecret } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Secret")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasSecret || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Secret")
            .disabled(disabled)
        }
    }
}
