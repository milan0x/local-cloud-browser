import SwiftUI

@MainActor
final class KinesisToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createStream
        case putRecord
        case deleteStream
    }

    func reset() {
        pendingAction = nil
    }
}

struct KinesisToolbar: ToolbarContent {
    @ObservedObject var state: KinesisToolbarState
    let isReadOnly: Bool
    let hasStream: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createStream } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Stream")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .putRecord } label: {
                Label("Put Record", systemImage: "arrow.up.doc")
                    .toolbarHitTarget()
            }
            .help("Put Record")
            .disabled(!hasStream || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasStream || isReadOnly
            Button { state.pendingAction = .deleteStream } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Stream")
            .disabled(disabled)
        }
    }
}
