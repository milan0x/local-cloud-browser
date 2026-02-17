import SwiftUI

struct APIGatewayModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: APIGatewayService
    @StateObject private var toolbarState = APIGatewayToolbarState()

    @State private var selectedAPIIDs: Set<RestApi.ID> = []
    @State private var activeAPI: RestApi?

    // Session restore: captured once when the view is created
    @State private var restoreAPIId: String?

    init() {
        _service = StateObject(wrappedValue: APIGatewayService())
        if let saved = LastSessionStore.load() {
            _restoreAPIId = State(initialValue: saved.apiGatewayAPIId)
        }
    }

    var body: some View {
        HSplitView {
            APIGatewayAPIListView(
                service: service,
                toolbarState: toolbarState,
                selectedAPIIDs: $selectedAPIIDs,
                activeAPI: $activeAPI,
                restoreAPIId: restoreAPIId
            )
            .frame(width: 280)

            Group {
                if let api = activeAPI {
                    APIGatewayAPIBrowserView(
                        service: service,
                        api: api,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "network", message: "Select a REST API")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            APIGatewayToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasAPI: activeAPI != nil
            )
        }
        .onChange(of: activeAPI) {
            toolbarState.reset()
            LastSessionStore.saveAPIGatewayAPI(activeAPI?.id)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct APIGatewayModule: LocalStackModule {
    let serviceName = "API Gateway"
    let serviceIcon = "network"
    let serviceEndpoint = "/restapis"

    func makeMainView() -> AnyView {
        AnyView(APIGatewayModuleView())
    }
}
