import SwiftUI

@MainActor
final class SESToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case verifyIdentity
        case sendEmail
        case clearSentEmails
        case deleteIdentity
    }

    func reset() {
        pendingAction = nil
    }
}

struct SESToolbar: ToolbarContent {
    @ObservedObject var state: SESToolbarState
    let isReadOnly: Bool
    let hasIdentity: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .verifyIdentity } label: {
                Label("Verify", systemImage: "checkmark.seal")
                    .toolbarHitTarget()
            }
            .help("Verify Identity")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .sendEmail } label: {
                Label("Send", systemImage: "paperplane")
                    .toolbarHitTarget()
            }
            .help("Send Email")
            .disabled(isReadOnly || !hasIdentity)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .clearSentEmails } label: {
                Label("Clear", systemImage: "trash.circle")
                    .toolbarHitTarget()
            }
            .help("Clear Sent Emails")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasIdentity || isReadOnly
            Button { state.pendingAction = .deleteIdentity } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Identity")
            .disabled(disabled)
        }
    }
}
