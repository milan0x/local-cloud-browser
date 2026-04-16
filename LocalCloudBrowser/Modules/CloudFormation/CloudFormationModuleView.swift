import SwiftUI

struct CloudFormationModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: CloudFormationService
    @StateObject private var toolbarState = CloudFormationToolbarState()

    @State private var selectedStackIDs: Set<CloudFormationStack.ID> = []
    @State private var activeStack: CloudFormationStack?

    // Session restore: captured once when the view is created
    @State private var restoreStackName: String?

    init() {
        _service = StateObject(wrappedValue: CloudFormationService())
        if let saved = LastSessionStore.load() {
            _restoreStackName = State(initialValue: saved.cloudFormationStackName)
        }
    }

    var body: some View {
        HSplitView {
            CloudFormationStackListView(
                service: service,
                toolbarState: toolbarState,
                selectedStackIDs: $selectedStackIDs,
                activeStack: $activeStack,
                restoreStackName: restoreStackName
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)

            Group {
                if let stack = activeStack {
                    CloudFormationStackBrowserView(
                        service: service,
                        stack: stack,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "square.stack.3d.down.right", message: "Select a stack")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
        }
        .toolbar {
            CloudFormationToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasStack: activeStack != nil
            )
        }
        .onChange(of: activeStack) {
            toolbarState.reset()
            LastSessionStore.saveCloudFormationStack(activeStack?.stackName)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct CloudFormationModule: ServiceModule {
    let serviceName = "CloudFormation"
    let serviceIcon = "square.stack.3d.down.right"
    let serviceEndpoint = "/cloudformation"

    func makeMainView() -> AnyView {
        AnyView(CloudFormationModuleView())
    }
}
