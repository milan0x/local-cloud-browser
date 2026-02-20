import SwiftUI

@MainActor
final class KMSToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case createKey
        case toggleEnabled
        case scheduleDeletion
    }

    func reset() {
        pendingAction = nil
    }
}

struct KMSToolbar: ToolbarContent {
    @ObservedObject var state: KMSToolbarState
    let isReadOnly: Bool
    let hasKey: Bool
    let keyEnabled: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Key Details")
            .disabled(!hasKey)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createKey } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Key")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .toggleEnabled } label: {
                Label(
                    keyEnabled ? "Disable" : "Enable",
                    systemImage: keyEnabled ? "pause.circle" : "play.circle"
                )
                .toolbarHitTarget()
            }
            .help(keyEnabled ? "Disable Key" : "Enable Key")
            .disabled(!hasKey || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasKey || isReadOnly
            Button { state.pendingAction = .scheduleDeletion } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Schedule Key Deletion")
            .disabled(disabled)
        }
    }
}
