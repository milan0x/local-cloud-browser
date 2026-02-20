import SwiftUI

@MainActor
final class SNSToolbarState: ObservableObject {
    @Published var pendingAction: Action?
    @Published var hasSubscriptionSelection = false

    enum Action: Equatable {
        case publish
        case subscribe
        case showAttributes
        case unsubscribeSelected
    }

    func reset() {
        hasSubscriptionSelection = false
        pendingAction = nil
    }
}

struct SNSToolbar: ToolbarContent {
    @ObservedObject var state: SNSToolbarState
    let isReadOnly: Bool
    let hasTopic: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .showAttributes } label: {
                Label("Attributes", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Topic Attributes")
            .disabled(!hasTopic)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .publish } label: {
                Label("Publish", systemImage: "paperplane")
                    .toolbarHitTarget()
            }
            .help("Publish Message")
            .disabled(!hasTopic || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .subscribe } label: {
                Label("Subscribe", systemImage: "plus.circle")
                    .toolbarHitTarget()
            }
            .help("Add Subscription")
            .disabled(!hasTopic || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasTopic || isReadOnly || !state.hasSubscriptionSelection
            Button { state.pendingAction = .unsubscribeSelected } label: {
                Label("Unsubscribe", systemImage: "minus.circle")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Unsubscribe Selected")
            .disabled(disabled)
        }
    }
}
