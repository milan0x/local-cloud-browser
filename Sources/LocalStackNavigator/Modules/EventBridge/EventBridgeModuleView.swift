import SwiftUI

struct EventBridgeModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: EventBridgeService
    @StateObject private var toolbarState = EventBridgeToolbarState()

    @State private var selectedBusIDs: Set<EventBridgeBus.ID> = []
    @State private var activeBus: EventBridgeBus?

    // Session restore: captured once when the view is created
    @State private var restoreBusName: String?

    init() {
        _service = StateObject(wrappedValue: EventBridgeService())
        if let saved = LastSessionStore.load() {
            _restoreBusName = State(initialValue: saved.eventBridgeBusName)
        }
    }

    var body: some View {
        HSplitView {
            EventBridgeBusListView(
                service: service,
                toolbarState: toolbarState,
                selectedBusIDs: $selectedBusIDs,
                activeBus: $activeBus,
                restoreBusName: restoreBusName
            )
            .frame(width: 260)

            Group {
                if let bus = activeBus {
                    EventBridgeRuleBrowserView(
                        service: service,
                        bus: bus,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select an event bus")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            EventBridgeToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasBus: activeBus != nil
            )
        }
        .onChange(of: activeBus) {
            toolbarState.reset()
            LastSessionStore.saveEventBridgeBus(activeBus?.name)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct EventBridgeModule: LocalStackModule {
    let serviceName = "EventBridge"
    let serviceIcon = "bolt.horizontal"
    let serviceEndpoint = "/events"

    func makeMainView() -> AnyView {
        AnyView(EventBridgeModuleView())
    }
}
