import SwiftUI

struct EventBridgeModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: EventBridgeService
    @StateObject private var schedulerService: EventBridgeSchedulerService
    @StateObject private var toolbarState = EventBridgeToolbarState()

    @State private var tab: EventBridgeTab = .events

    // Events selection
    @State private var selectedBusIDs: Set<EventBridgeBus.ID> = []
    @State private var activeBus: EventBridgeBus?

    // Schedules selection
    @State private var selectedGroupIDs: Set<SchedulerScheduleGroup.ID> = []
    @State private var activeGroup: SchedulerScheduleGroup?

    // Session restore
    @State private var restoreBusName: String?
    @State private var restoreTab: EventBridgeTab?
    @State private var restoreGroupName: String?
    @State private var restoreScheduleName: String?

    init() {
        _service = StateObject(wrappedValue: EventBridgeService())
        _schedulerService = StateObject(wrappedValue: EventBridgeSchedulerService())
        if let saved = LastSessionStore.load() {
            _restoreBusName = State(initialValue: saved.eventBridgeBusName)
            if let tabStr = saved.eventBridgeTab, let tab = EventBridgeTab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
            _restoreGroupName = State(initialValue: saved.eventBridgeScheduleGroupName)
            _restoreScheduleName = State(initialValue: saved.eventBridgeScheduleName)
        }
    }

    var body: some View {
        ResizableSplitView(storageKey: "EventBridgePaneWidth") {
            leftPane
        } trailing: {
            Group {
                if tab == .events {
                    if let bus = activeBus {
                        EventBridgeRuleBrowserView(
                            service: service,
                            bus: bus,
                            toolbarState: toolbarState
                        )
                    } else {
                        EmptyDetailView(icon: "bolt.horizontal", message: "Select an event bus")
                    }
                } else {
                    if let group = activeGroup {
                        EventBridgeScheduleBrowserView(
                            service: schedulerService,
                            group: group,
                            toolbarState: toolbarState,
                            restoreScheduleName: restoreScheduleName
                        )
                    } else {
                        EmptyDetailView(icon: "calendar.badge.clock", message: "Select a schedule group")
                    }
                }
            }
        }
        .toolbar {
            EventBridgeToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                tab: tab,
                hasBus: activeBus != nil,
                hasScheduleGroup: activeGroup != nil
            )
        }
        .onChange(of: tab) {
            if tab == .events {
                selectedGroupIDs = []
                activeGroup = nil
            } else {
                selectedBusIDs = []
                activeBus = nil
            }
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeBus) {
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeGroup) {
            toolbarState.reset()
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
            schedulerService.updateClient(client)
            if let restoreTab {
                tab = restoreTab
            }
        }
    }

    // MARK: - Left Pane

    private var leftPane: some View {
        VStack(spacing: 0) {
            SegmentedTabPicker(selection: $tab)

            Divider()

            switch tab {
            case .events:
                EventBridgeBusListView(
                    service: service,
                    toolbarState: toolbarState,
                    selectedBusIDs: $selectedBusIDs,
                    activeBus: $activeBus,
                    restoreBusName: restoreBusName
                )
            case .schedules:
                EventBridgeScheduleGroupListView(
                    service: schedulerService,
                    toolbarState: toolbarState,
                    selectedGroupIDs: $selectedGroupIDs,
                    activeGroup: $activeGroup,
                    restoreGroupName: restoreGroupName
                )
            }
        }
    }


    // MARK: - Session

    private func saveSession() {
        LastSessionStore.saveEventBridge(
            tab: tab.rawValue,
            busName: activeBus?.name,
            scheduleGroupName: activeGroup?.name,
            scheduleName: nil
        )
    }
}

struct EventBridgeModule: ServiceModule {
    let serviceName = "EventBridge"
    let serviceIcon = "bolt.horizontal"
    let serviceEndpoint = "/events"

    func makeMainView() -> AnyView {
        AnyView(EventBridgeModuleView())
    }
}
