import SwiftUI

struct SecretsManagerModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SecretsManagerService
    @StateObject private var toolbarState = SecretsManagerToolbarState()

    @State private var selectedSecretIDs: Set<Secret.ID> = []
    @State private var activeSecret: Secret?

    // Session restore: captured once when the view is created
    @State private var restoreSecretName: String?

    init() {
        _service = StateObject(wrappedValue: SecretsManagerService())
        if let saved = LastSessionStore.load() {
            _restoreSecretName = State(initialValue: saved.secretName)
        }
    }

    var body: some View {
        HSplitView {
            SecretsListView(
                service: service,
                toolbarState: toolbarState,
                selectedSecretIDs: $selectedSecretIDs,
                activeSecret: $activeSecret,
                restoreSecretName: restoreSecretName
            )
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)

            Group {
                if let secret = activeSecret {
                    SecretValuePaneView(
                        service: service,
                        secret: secret,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "key", message: "Select a secret")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            SecretsManagerToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasSecret: activeSecret != nil
            )
        }
        .onChange(of: activeSecret) {
            toolbarState.reset()
            LastSessionStore.saveSecretsManagerSecret(activeSecret?.name)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SecretsManagerModule: ServiceModule {
    let serviceName = "Secrets Manager"
    let serviceIcon = "key"
    let serviceEndpoint = "/secretsmanager"

    func makeMainView() -> AnyView {
        AnyView(SecretsManagerModuleView())
    }
}
