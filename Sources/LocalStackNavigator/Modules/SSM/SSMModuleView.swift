import SwiftUI

struct SSMModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
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
            .frame(width: 280)

            Group {
                if let parameter = activeParameter {
                    SSMParameterValuePaneView(
                        service: service,
                        parameter: parameter,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a parameter")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct SSMModule: LocalStackModule {
    let serviceName = "Parameter Store"
    let serviceIcon = "list.bullet.rectangle"
    let serviceEndpoint = "/ssm"

    func makeMainView() -> AnyView {
        AnyView(SSMModuleView())
    }
}
