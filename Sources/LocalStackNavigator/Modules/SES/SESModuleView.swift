import SwiftUI

struct SESModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
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
        HSplitView {
            SESIdentityListView(
                service: service,
                toolbarState: toolbarState,
                selectedIdentityIDs: $selectedIdentityIDs,
                activeIdentity: $activeIdentity,
                restoreIdentityName: restoreIdentityName
            )
            .frame(width: 280)

            SESSentEmailBrowserView(
                service: service,
                toolbarState: toolbarState,
                selectedIdentity: activeIdentity
            )
            .frame(minWidth: 400)
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

struct SESModule: LocalStackModule {
    let serviceName = "SES"
    let serviceIcon = "envelope"
    let serviceEndpoint = "/ses"

    func makeMainView() -> AnyView {
        AnyView(SESModuleView())
    }
}
