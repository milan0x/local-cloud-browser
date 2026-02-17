import SwiftUI

struct StepFunctionsModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: StepFunctionsService
    @StateObject private var toolbarState = StepFunctionsToolbarState()

    @State private var selectedIDs: Set<StateMachineSummary.ID> = []
    @State private var activeMachine: StateMachineSummary?
    @State private var selectedTab: StepFunctionsTab = .definition
    @State private var showStartSheet = false

    // Session restore
    @State private var restoreName: String?
    @State private var restoreTab: StepFunctionsTab?

    init() {
        _service = StateObject(wrappedValue: StepFunctionsService())
        if let saved = LastSessionStore.load() {
            _restoreName = State(initialValue: saved.stepFunctionsStateMachineName)
            if let tabStr = saved.stepFunctionsTab,
               let tab = StepFunctionsTab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
        }
    }

    var body: some View {
        HSplitView {
            StepFunctionsStateMachineListView(
                service: service,
                toolbarState: toolbarState,
                selectedIDs: $selectedIDs,
                activeMachine: $activeMachine,
                restoreName: restoreName
            )
            .frame(width: 280)

            Group {
                if let machine = activeMachine {
                    detailPane(for: machine)
                } else {
                    EmptyDetailView(icon: "arrow.triangle.branch", message: "Select a state machine")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            StepFunctionsToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasStateMachine: activeMachine != nil
            )
        }
        .sheet(isPresented: $showStartSheet) {
            if let machine = activeMachine {
                StepFunctionsStartExecutionView(
                    service: service,
                    stateMachineArn: machine.stateMachineArn
                )
            }
        }
        .onChange(of: activeMachine) {
            toolbarState.reset()
            LastSessionStore.saveStepFunctions(
                tab: selectedTab.rawValue,
                stateMachineName: activeMachine?.name
            )
        }
        .onChange(of: selectedTab) {
            LastSessionStore.saveStepFunctions(
                tab: selectedTab.rawValue,
                stateMachineName: activeMachine?.name
            )
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            if action == .startExecution {
                toolbarState.pendingAction = nil
                showStartSheet = true
            }
        }
        .onAppear {
            service.updateClient(client)
            if let tab = restoreTab {
                selectedTab = tab
                restoreTab = nil
            }
        }
    }

    @ViewBuilder
    private func detailPane(for machine: StateMachineSummary) -> some View {
        VStack(spacing: 0) {
            SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 12, verticalPadding: 8)

            Divider()

            switch selectedTab {
            case .definition:
                StepFunctionsDefinitionView(
                    service: service,
                    stateMachineArn: machine.stateMachineArn
                )
            case .executions:
                StepFunctionsExecutionListView(
                    service: service,
                    stateMachine: machine
                )
            }
        }
    }
}

struct StepFunctionsModule: LocalStackModule {
    let serviceName = "Step Functions"
    let serviceIcon = "arrow.triangle.branch"
    let serviceEndpoint = "/stepfunctions"

    func makeMainView() -> AnyView {
        AnyView(StepFunctionsModuleView())
    }
}
