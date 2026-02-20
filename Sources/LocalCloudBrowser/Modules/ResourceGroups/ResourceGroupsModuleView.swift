import SwiftUI

struct ResourceGroupsModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: ResourceGroupsService
    @StateObject private var toolbarState = ResourceGroupsToolbarState()

    @State private var selectedGroupIDs: Set<ResourceGroupSummary.ID> = []
    @State private var activeGroup: ResourceGroupSummary?

    // Session restore: captured once when the view is created
    @State private var restoreGroupName: String?

    init() {
        _service = StateObject(wrappedValue: ResourceGroupsService())
        if let saved = LastSessionStore.load() {
            _restoreGroupName = State(initialValue: saved.resourceGroupName)
        }
    }

    var body: some View {
        HSplitView {
            ResourceGroupsListView(
                service: service,
                toolbarState: toolbarState,
                selectedGroupIDs: $selectedGroupIDs,
                activeGroup: $activeGroup,
                restoreGroupName: restoreGroupName
            )
            .frame(width: 280)

            Group {
                if let group = activeGroup {
                    ResourceGroupsDetailPaneView(
                        service: service,
                        group: group
                    )
                } else {
                    EmptyDetailView(icon: "square.3.layers.3d", message: "Select a group")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            ResourceGroupsToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasGroup: activeGroup != nil
            )
        }
        .onChange(of: activeGroup) {
            toolbarState.reset()
            LastSessionStore.saveResourceGroup(activeGroup?.name)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct ResourceGroupsModule: ServiceModule {
    let serviceName = "Resource Groups"
    let serviceIcon = "square.3.layers.3d"
    let serviceEndpoint = "/resource-groups"

    func makeMainView() -> AnyView {
        AnyView(ResourceGroupsModuleView())
    }
}
