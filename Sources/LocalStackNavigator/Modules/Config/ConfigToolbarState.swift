import SwiftUI

@MainActor
final class ConfigToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createRecorder
        case deleteRecorder
        case createChannel
        case deleteChannel
    }

    func reset() {
        pendingAction = nil
    }
}

struct ConfigToolbar: ToolbarContent {
    @ObservedObject var state: ConfigToolbarState
    let isReadOnly: Bool
    let tab: ConfigTab
    let hasRecorder: Bool
    let hasChannel: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.pendingAction = tab == .recorders ? .createRecorder : .createChannel
            } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help(tab == .recorders ? "Create Recorder" : "Create Delivery Channel")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let hasSelection = tab == .recorders ? hasRecorder : hasChannel
            let disabled = !hasSelection || isReadOnly
            Button {
                state.pendingAction = tab == .recorders ? .deleteRecorder : .deleteChannel
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help(tab == .recorders ? "Delete Recorder" : "Delete Delivery Channel")
            .disabled(disabled)
        }
    }
}
