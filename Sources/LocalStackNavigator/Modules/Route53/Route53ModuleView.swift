import SwiftUI

struct Route53ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: Route53Service
    @StateObject private var resolverService: Route53ResolverService
    @StateObject private var toolbarState = Route53ToolbarState()

    @State private var tab: Route53Tab = .zones

    // Zones selection
    @State private var selectedZoneIDs: Set<Route53HostedZone.ID> = []
    @State private var activeZone: Route53HostedZone?

    // Resolver selection
    @State private var selectedEndpointIDs: Set<ResolverEndpoint.ID> = []
    @State private var activeEndpoint: ResolverEndpoint?

    // Session restore
    @State private var restoreZoneId: String?
    @State private var restoreTab: Route53Tab?
    @State private var restoreEndpointId: String?

    init() {
        _service = StateObject(wrappedValue: Route53Service())
        _resolverService = StateObject(wrappedValue: Route53ResolverService())
        if let saved = LastSessionStore.load() {
            _restoreZoneId = State(initialValue: saved.route53HostedZoneId)
            if let tabStr = saved.route53Tab, let tab = Route53Tab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
            _restoreEndpointId = State(initialValue: saved.route53ResolverEndpointId)
        }
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(width: 280)

            Group {
                if tab == .zones {
                    if let zone = activeZone {
                        Route53RecordSetBrowserView(
                            service: service,
                            zone: zone,
                            toolbarState: toolbarState
                        )
                    } else {
                        emptyDetail("Select a hosted zone", icon: "globe.americas")
                    }
                } else {
                    if let endpoint = activeEndpoint {
                        Route53ResolverDetailView(
                            service: resolverService,
                            endpoint: endpoint
                        )
                    } else {
                        emptyDetail("Select a resolver endpoint", icon: "network")
                    }
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            Route53Toolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                tab: tab,
                hasZone: activeZone != nil,
                hasEndpoint: activeEndpoint != nil
            )
        }
        .onChange(of: tab) {
            if tab == .zones {
                selectedEndpointIDs = []
                activeEndpoint = nil
            } else {
                selectedZoneIDs = []
                activeZone = nil
            }
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeZone) {
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeEndpoint) {
            toolbarState.reset()
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
            resolverService.updateClient(client)
            if let restoreTab {
                tab = restoreTab
            }
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            SegmentedTabPicker(selection: $tab)

            Divider()

            switch tab {
            case .zones:
                Route53ZoneListView(
                    service: service,
                    toolbarState: toolbarState,
                    selectedZoneIDs: $selectedZoneIDs,
                    activeZone: $activeZone,
                    restoreZoneId: restoreZoneId
                )
            case .resolver:
                Route53ResolverListView(
                    service: resolverService,
                    toolbarState: toolbarState,
                    selectedEndpointIDs: $selectedEndpointIDs,
                    activeEndpoint: $activeEndpoint,
                    restoreEndpointId: restoreEndpointId
                )
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Route 53")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {}

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                toolbarState.pendingAction = tab == .zones ? .createZone : .createEndpoint
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {}

            ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled) {
                toolbarState.pendingAction = tab == .zones ? .deleteZone : .deleteEndpoint
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var deleteDisabled: Bool {
        let hasSelection = tab == .zones ? activeZone != nil : activeEndpoint != nil
        return !hasSelection || appState.isReadOnly
    }

    private func emptyDetail(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session

    private func saveSession() {
        LastSessionStore.saveRoute53(
            tab: tab.rawValue,
            hostedZoneId: activeZone?.id,
            resolverEndpointId: activeEndpoint?.id
        )
    }
}

struct Route53Module: LocalStackModule {
    let serviceName = "Route 53"
    let serviceIcon = "globe.americas"
    let serviceEndpoint = "/route53"

    func makeMainView() -> AnyView {
        AnyView(Route53ModuleView())
    }
}
