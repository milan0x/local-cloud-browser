import SwiftUI

@MainActor
final class APIGatewayToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case viewDetails
        case createResource
        case addMethod
        case createDeployment
        case createStage
        case deleteSelected
    }

    func reset() {
        pendingAction = nil
    }
}

struct APIGatewayToolbar: ToolbarContent {
    @ObservedObject var state: APIGatewayToolbarState
    let isReadOnly: Bool
    let hasAPI: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .viewDetails } label: {
                Label("Details", systemImage: "info.circle")
                    .toolbarHitTarget()
            }
            .help("API Details")
            .disabled(!hasAPI)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createResource } label: {
                Label("Resource", systemImage: "folder.badge.plus")
                    .toolbarHitTarget()
            }
            .help("Create Resource")
            .disabled(!hasAPI || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createDeployment } label: {
                Label("Deploy", systemImage: "arrow.up.circle")
                    .toolbarHitTarget()
            }
            .help("Create Deployment")
            .disabled(!hasAPI || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createStage } label: {
                Label("Stage", systemImage: "flag")
                    .toolbarHitTarget()
            }
            .help("Create Stage")
            .disabled(!hasAPI || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasAPI || isReadOnly
            Button { state.pendingAction = .deleteSelected } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete API")
            .disabled(disabled)
        }
    }
}
