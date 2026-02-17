import SwiftUI

struct RedshiftModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: RedshiftService
    @StateObject private var toolbarState = RedshiftToolbarState()

    @State private var selectedClusterIDs: Set<RedshiftCluster.ID> = []
    @State private var activeCluster: RedshiftCluster?

    // Session restore: captured once when the view is created
    @State private var restoreClusterId: String?

    init() {
        _service = StateObject(wrappedValue: RedshiftService())
        if let saved = LastSessionStore.load() {
            _restoreClusterId = State(initialValue: saved.redshiftClusterIdentifier)
        }
    }

    var body: some View {
        HSplitView {
            RedshiftClusterListView(
                service: service,
                toolbarState: toolbarState,
                selectedClusterIDs: $selectedClusterIDs,
                activeCluster: $activeCluster,
                restoreClusterId: restoreClusterId
            )
            .frame(width: 280)

            Group {
                if let cluster = activeCluster {
                    RedshiftClusterDetailPaneView(
                        service: service,
                        cluster: cluster,
                        toolbarState: toolbarState
                    )
                } else {
                    EmptyDetailView(icon: "cylinder.split.1x2", message: "Select a cluster")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            RedshiftToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasCluster: activeCluster != nil
            )
        }
        .onChange(of: activeCluster) {
            toolbarState.reset()
            LastSessionStore.saveRedshiftCluster(activeCluster?.clusterIdentifier)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct RedshiftModule: LocalStackModule {
    let serviceName = "Redshift"
    let serviceIcon = "cylinder.split.1x2"
    let serviceEndpoint = "/redshift"

    func makeMainView() -> AnyView {
        AnyView(RedshiftModuleView())
    }
}
