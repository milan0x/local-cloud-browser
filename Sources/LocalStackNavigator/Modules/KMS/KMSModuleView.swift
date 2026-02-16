import SwiftUI

struct KMSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
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
            .frame(width: 280)

            Group {
                if let key = activeKey {
                    KMSKeyDetailPaneView(
                        service: service,
                        key: key,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a key")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct KMSModule: LocalStackModule {
    let serviceName = "KMS"
    let serviceIcon = "lock.shield"
    let serviceEndpoint = "/kms"

    func makeMainView() -> AnyView {
        AnyView(KMSModuleView())
    }
}
