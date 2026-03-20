import SwiftUI

struct LambdaModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: LambdaService
    @StateObject private var toolbarState = LambdaToolbarState()

    @State private var selectedFunctionIDs: Set<LambdaFunction.ID> = []
    @State private var activeFunction: LambdaFunction?

    // Pane focus
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var listPaneFocusTrigger = 0
    @State private var detailPaneFocusTrigger = 0

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
                restoreFunctionName: restoreFunctionName,
                searchFocusTrigger: listSearchFocusTrigger,
                paneFocusTrigger: listPaneFocusTrigger
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                appState.sidebarFocusTrigger += 1
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                guard activeFunction != nil else { return .ignored }
                detailPaneFocusTrigger += 1
                return .handled
            }

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
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                listPaneFocusTrigger += 1
                return .handled
            }
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
        .cmdFSearchCycling(
            hasDetail: activeFunction != nil,
            activeItemID: activeFunction?.id,
            listSearchFocusTrigger: $listSearchFocusTrigger,
            detailSearchFocusTrigger: $detailSearchFocusTrigger
        )
        .onChange(of: appState.moduleListFocusTrigger) {
            listPaneFocusTrigger += 1
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
