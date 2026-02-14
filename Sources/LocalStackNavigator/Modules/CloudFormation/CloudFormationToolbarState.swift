import SwiftUI

@MainActor
final class CloudFormationToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createStack
        case viewDetails
        case viewTemplate
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct CloudFormationToolbar: ToolbarContent {
    @ObservedObject var state: CloudFormationToolbarState
    let isReadOnly: Bool
    let hasStack: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("Stack Details")
            .disabled(!hasStack)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewTemplate } label: {
                Label("Template", systemImage: "doc.text")
                    .toolbarHitTarget()
            }
            .help("View Template")
            .disabled(!hasStack)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createStack } label: {
                Label("Create Stack", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create Stack")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasStack || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete Stack")
            .disabled(disabled)
        }
    }
}
