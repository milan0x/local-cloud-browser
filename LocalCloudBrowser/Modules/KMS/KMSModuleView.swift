import SwiftUI

struct KMSModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: KMSService
    @StateObject private var toolbarState = KMSToolbarState()

    @State private var selectedKeyIDs: Set<KMSKey.ID> = []
    @State private var activeKey: KMSKey?

    // Session restore: captured once when the view is created
    @State private var restoreKeyId: String?

    init() {
        _service = StateObject(wrappedValue: KMSService())
        if let saved = LastSessionStore.load() {
            _restoreKeyId = State(initialValue: saved.kmsKeyId)
        }
    }

    var body: some View {
        HSplitView {
            KMSKeyListView(
                service: service,
                toolbarState: toolbarState,
                selectedKeyIDs: $selectedKeyIDs,
                activeKey: $activeKey,
                restoreKeyId: restoreKeyId
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)

            Group {
                if let key = activeKey {
                    KMSKeyDetailPaneView(
                        service: service,
                        key: key,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "lock.shield", message: "Select a key")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            KMSToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasKey: activeKey != nil,
                keyEnabled: activeKey?.enabled ?? false
            )
        }
        .onChange(of: activeKey) {
            toolbarState.reset()
            LastSessionStore.saveKMSKey(activeKey?.keyId)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct KMSModule: ServiceModule {
    let serviceName = "KMS"
    let serviceIcon = "lock.shield"
    let serviceEndpoint = "/kms"

    func makeMainView() -> AnyView {
        AnyView(KMSModuleView())
    }
}
