import SwiftUI

struct SESModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SESService
    @StateObject private var toolbarState = SESToolbarState()

    @State private var selectedIdentityIDs: Set<SESIdentity.ID> = []
    @State private var activeIdentity: SESIdentity?

    // Session restore: captured once when the view is created
    @State private var restoreIdentityName: String?

    init() {
        _service = StateObject(wrappedValue: SESService())
        if let saved = LastSessionStore.load() {
            _restoreIdentityName = State(initialValue: saved.sesIdentityName)
        }
    }

    var body: some View {
        ResizableSplitView(storageKey: "SESPaneWidth") {
            SESIdentityListView(
                service: service,
                toolbarState: toolbarState,
                selectedIdentityIDs: $selectedIdentityIDs,
                activeIdentity: $activeIdentity,
                restoreIdentityName: restoreIdentityName
            )
        } trailing: {
            SESSentEmailBrowserView(
                service: service,
                toolbarState: toolbarState,
                selectedIdentity: activeIdentity
            )
        }
        .toolbar {
            SESToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasIdentity: activeIdentity != nil
            )
        }
        .onChange(of: activeIdentity) {
            toolbarState.reset()
            LastSessionStore.saveSESIdentity(activeIdentity?.identity)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SESModule: ServiceModule {
    let serviceName = "SES"
    let serviceIcon = "envelope"
    let serviceEndpoint = "/ses"

    func makeMainView() -> AnyView {
        AnyView(SESModuleView())
    }
}
