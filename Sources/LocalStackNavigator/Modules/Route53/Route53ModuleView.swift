import SwiftUI

struct Route53ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: Route53Service
    @StateObject private var toolbarState = Route53ToolbarState()

    @State private var selectedZoneIDs: Set<Route53HostedZone.ID> = []
    @State private var activeZone: Route53HostedZone?

    // Session restore: captured once when the view is created
    @State private var restoreZoneId: String?

    init() {
        _service = StateObject(wrappedValue: Route53Service())
        if let saved = LastSessionStore.load() {
            _restoreZoneId = State(initialValue: saved.route53HostedZoneId)
        }
    }

    var body: some View {
        HSplitView {
            Route53ZoneListView(
                service: service,
                toolbarState: toolbarState,
                selectedZoneIDs: $selectedZoneIDs,
                activeZone: $activeZone,
                restoreZoneId: restoreZoneId
            )
            .frame(width: 260)

            Group {
                if let zone = activeZone {
                    Route53RecordSetBrowserView(
                        service: service,
                        zone: zone,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a hosted zone")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            Route53Toolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasZone: activeZone != nil
            )
        }
        .onChange(of: activeZone) {
            toolbarState.reset()
            LastSessionStore.saveRoute53HostedZone(activeZone?.id)
        }
        .onAppear {
            service.updateClient(client)
        }
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
