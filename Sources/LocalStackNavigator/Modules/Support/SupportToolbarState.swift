import SwiftUI

@MainActor
final class SupportToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case create
        case resolve
    }

    func reset() {
        pendingAction = nil
    }
}

struct SupportToolbar: ToolbarContent {
    @ObservedObject var state: SupportToolbarState
    let isReadOnly: Bool
    let hasCase: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .create } label: {
                Label("Create Case", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Case")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasCase || isReadOnly
            Button { state.pendingAction = .resolve } label: {
                Label("Resolve", systemImage: "checkmark.circle")
                    .foregroundStyle(disabled ? .gray : .green)
                    .toolbarHitTarget()
            }
            .help("Resolve Case")
            .disabled(disabled)
        }
    }
}
