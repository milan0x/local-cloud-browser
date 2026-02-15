import SwiftUI

struct ACMModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: ACMService
    @StateObject private var toolbarState = ACMToolbarState()

    @State private var selectedCertIDs: Set<ACMCertificateSummary.ID> = []
    @State private var activeCertificate: ACMCertificateSummary?

    // Session restore: captured once when the view is created
    @State private var restoreCertArn: String?

    init() {
        _service = StateObject(wrappedValue: ACMService())
        if let saved = LastSessionStore.load() {
            _restoreCertArn = State(initialValue: saved.acmCertificateArn)
        }
    }

    var body: some View {
        HSplitView {
            ACMCertificateListView(
                service: service,
                toolbarState: toolbarState,
                selectedCertIDs: $selectedCertIDs,
                activeCertificate: $activeCertificate,
                restoreCertArn: restoreCertArn
            )
            .frame(width: 260)

            Group {
                if let cert = activeCertificate {
                    ACMCertificateDetailPaneView(
                        service: service,
                        certificate: cert
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a certificate")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            ACMToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasCertificate: activeCertificate != nil
            )
        }
        .onChange(of: activeCertificate) {
            toolbarState.reset()
            LastSessionStore.saveACMCertificate(activeCertificate?.certificateArn)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct ACMModule: LocalStackModule {
    let serviceName = "ACM"
    let serviceIcon = "checkmark.seal"
    let serviceEndpoint = "/acm"

    func makeMainView() -> AnyView {
        AnyView(ACMModuleView())
    }
}
