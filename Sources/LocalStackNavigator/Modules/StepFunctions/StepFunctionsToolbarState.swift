import SwiftUI

@MainActor
final class StepFunctionsToolbarState: ObservableObject {
    @Published var pendingAction: Action?

    enum Action: Equatable {
        case createStateMachine
        case startExecution
        case deleteStateMachine
    }

    func reset() {
        pendingAction = nil
    }
}

struct StepFunctionsToolbar: ToolbarContent {
    @ObservedObject var state: StepFunctionsToolbarState
    let isReadOnly: Bool
    let hasStateMachine: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .createStateMachine } label: {
                Label("Create", systemImage: "plus")
                    .toolbarHitTarget()
            }
            .help("Create State Machine")
            .disabled(isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { state.pendingAction = .startExecution } label: {
                Label("Start Execution", systemImage: "play")
                    .toolbarHitTarget()
            }
            .help("Start Execution")
            .disabled(!hasStateMachine || isReadOnly)
        }
        ToolbarItem(placement: .primaryAction) {
            let disabled = !hasStateMachine || isReadOnly
            Button { state.pendingAction = .deleteStateMachine } label: {
                Label("Delete", systemImage: "trash")
                    .foregroundStyle(disabled ? .gray : .red)
                    .toolbarHitTarget()
            }
            .help("Delete State Machine")
            .disabled(disabled)
        }
    }
}
