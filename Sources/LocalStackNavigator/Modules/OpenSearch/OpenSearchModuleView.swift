import SwiftUI

struct OpenSearchModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: OpenSearchService
    @StateObject private var toolbarState = OpenSearchToolbarState()

    @State private var selectedDomainIDs: Set<OpenSearchDomain.ID> = []
    @State private var activeDomain: OpenSearchDomain?

    // Session restore: captured once when the view is created
    @State private var restoreDomainName: String?

    init() {
        _service = StateObject(wrappedValue: OpenSearchService())
        if let saved = LastSessionStore.load() {
            _restoreDomainName = State(initialValue: saved.opensearchDomainName)
        }
    }

    var body: some View {
        HSplitView {
            OpenSearchDomainListView(
                service: service,
                toolbarState: toolbarState,
                selectedDomainIDs: $selectedDomainIDs,
                activeDomain: $activeDomain,
                restoreDomainName: restoreDomainName
            )
            .frame(width: 280)

            Group {
                if let domain = activeDomain {
                    OpenSearchDomainDetailView(
                        service: service,
                        domain: domain,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a domain")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            OpenSearchToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasDomain: activeDomain != nil
            )
        }
        .onChange(of: activeDomain) {
            toolbarState.reset()
            LastSessionStore.saveOpenSearchDomain(activeDomain?.domainName)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct OpenSearchModule: LocalStackModule {
    let serviceName = "OpenSearch"
    let serviceIcon = "magnifyingglass.circle"
    let serviceEndpoint = "/opensearch"

    func makeMainView() -> AnyView {
        AnyView(OpenSearchModuleView())
    }
}
