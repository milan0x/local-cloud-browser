import SwiftUI

struct SSMModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SSMService
    @StateObject private var toolbarState = SSMToolbarState()

    @State private var selectedParameterIDs: Set<SSMParameter.ID> = []
    @State private var activeParameter: SSMParameter?

    // Session restore: captured once when the view is created
    @State private var restoreParameterName: String?

    init() {
        _service = StateObject(wrappedValue: SSMService())
        if let saved = LastSessionStore.load() {
            _restoreParameterName = State(initialValue: saved.ssmParameterName)
        }
    }

    var body: some View {
        HSplitView {
            SSMParameterListView(
                service: service,
                toolbarState: toolbarState,
                selectedParameterIDs: $selectedParameterIDs,
                activeParameter: $activeParameter,
                restoreParameterName: restoreParameterName
            )
            .frame(minWidth: 250, idealWidth: 280, maxWidth: 450)

            Group {
                if let parameter = activeParameter {
                    SSMParameterValuePaneView(
                        service: service,
                        parameter: parameter,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "list.bullet.rectangle", message: "Select a parameter")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            SSMToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasParameter: activeParameter != nil
            )
        }
        .onChange(of: activeParameter) {
            toolbarState.reset()
            LastSessionStore.saveSSMParameter(activeParameter?.name)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SSMModule: ServiceModule {
    let serviceName = "Parameter Store"
    let serviceIcon = "list.bullet.rectangle"
    let serviceEndpoint = "/ssm"

    func makeMainView() -> AnyView {
        AnyView(SSMModuleView())
    }
}
