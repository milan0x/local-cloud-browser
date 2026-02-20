import SwiftUI

struct LambdaModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: LambdaService
    @StateObject private var toolbarState = LambdaToolbarState()

    @State private var selectedFunctionIDs: Set<LambdaFunction.ID> = []
    @State private var activeFunction: LambdaFunction?

    // Session restore: captured once when the view is created
    @State private var restoreFunctionName: String?

    init() {
        _service = StateObject(wrappedValue: LambdaService())
        if let saved = LastSessionStore.load() {
            _restoreFunctionName = State(initialValue: saved.lambdaFunctionName)
        }
    }

    var body: some View {
        HSplitView {
            LambdaFunctionListView(
                service: service,
                toolbarState: toolbarState,
                selectedFunctionIDs: $selectedFunctionIDs,
                activeFunction: $activeFunction,
                restoreFunctionName: restoreFunctionName
            )
            .frame(width: 280)

            Group {
                if let function = activeFunction {
                    LambdaFunctionDetailPaneView(
                        service: service,
                        function: function,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "function", message: "Select a function")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            LambdaToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasFunction: activeFunction != nil
            )
        }
        .onChange(of: activeFunction) {
            toolbarState.reset()
            LastSessionStore.saveLambdaFunction(activeFunction?.functionName)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct LambdaModule: ServiceModule {
    let serviceName = "Lambda"
    let serviceIcon = "function"
    let serviceEndpoint = "/lambda"

    func makeMainView() -> AnyView {
        AnyView(LambdaModuleView())
    }
}
