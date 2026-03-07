import SwiftUI

@MainActor
final class KinesisToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createStream
        case putRecord
        case deleteStream
        case createDeliveryStream
        case putFirehoseRecord
        case deleteDeliveryStream
    }

    func reset() {
        pendingAction = nil
    }
}

struct KinesisToolbar: ToolbarContent {
    @ObservedObject var state: KinesisToolbarState
    let isReadOnly: Bool
    let tab: KinesisTab
    let hasStream: Bool
    let hasDeliveryStream: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.pendingAction = tab == .streams ? .createStream : .createDeliveryStream
            } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help(tab == .streams ? "Create Stream" : "Create Delivery Stream")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let hasSelection = tab == .streams ? hasStream : hasDeliveryStream
            Button {
                state.pendingAction = tab == .streams ? .putRecord : .putFirehoseRecord
            } label: {
                Label("Put Record", systemImage: "arrow.up.doc")
                    .toolbarHitTarget()
            }
            .help("Put Record")
            .disabled(!hasSelection || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let hasSelection = tab == .streams ? hasStream : hasDeliveryStream
            let disabled = !hasSelection || isReadOnly
            Button {
                state.pendingAction = tab == .streams ? .deleteStream : .deleteDeliveryStream
            } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help(tab == .streams ? "Delete Stream" : "Delete Delivery Stream")
            .disabled(disabled)
        }
    }
}
