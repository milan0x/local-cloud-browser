import SwiftUI

@MainActor
final class SQSToolbarState: ObservableObject {
    @Published var pendingAction: Action?
    @Published var isLoading = false
    @Published var hasSelection = false

    enum Action: Equatable {
        case createQueue
        case deleteSelected
        case purgeSelected
        case sendMessage
        case receiveMessages
        case showAttributes
    }

    func reset() {
        isLoading = false
        hasSelection = false
        pendingAction = nil
    }
}

struct SQSToolbar: ToolbarContent {
    @ObservedObject var state: SQSToolbarState
    let isReadOnly: Bool
    let hasQueue: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .showAttributes } label: {
                Label("Attributes", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Queue Attributes")
            .disabled(!hasQueue)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .sendMessage } label: {
                Label("Send", systemImage: "paperplane")
                    .toolbarHitTarget()
            }
            .help("Send Message")
            .disabled(!hasQueue || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .receiveMessages } label: {
                Label("Receive", systemImage: "tray.and.arrow.down")
                    .toolbarHitTarget()
            }
            .help("Receive Messages")
            .disabled(!hasQueue)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .purgeSelected } label: {
                Label("Purge", systemImage: "arrow.counterclockwise")
                    .toolbarHitTarget()
            }
            .help("Purge Queue")
            .disabled(!hasQueue || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasQueue || isReadOnly || !state.hasSelection
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Selected Messages")
            .disabled(disabled)
        }
    }
}
