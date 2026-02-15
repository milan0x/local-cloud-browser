import SwiftUI

@MainActor
final class ACMToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case requestCertificate
        case importCertificate
        case deleteCertificate
    }

    func reset() {
        pendingAction = nil
    }
}

struct ACMToolbar: ToolbarContent {
    @ObservedObject var state: ACMToolbarState
    let isReadOnly: Bool
    let hasCertificate: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .requestCertificate } label: {
                Label("Request", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Request Certificate")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .importCertificate } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .toolbarHitTarget()
            }
            .help("Import Certificate")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasCertificate || isReadOnly
            Button { state.pendingAction = .deleteCertificate } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Certificate")
            .disabled(disabled)
        }
    }
}
