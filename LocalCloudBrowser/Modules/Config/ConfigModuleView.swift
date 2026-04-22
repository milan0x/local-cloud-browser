import SwiftUI

struct ConfigModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: ConfigService
    @StateObject private var toolbarState = ConfigToolbarState()

    @State private var tab: ConfigTab = .recorders

    // Recorders selection
    @State private var selectedRecorderIDs: Set<ConfigurationRecorder.ID> = []
    @State private var activeRecorder: ConfigurationRecorder?

    // Delivery Channels selection
    @State private var selectedChannelIDs: Set<DeliveryChannel.ID> = []
    @State private var activeChannel: DeliveryChannel?

    // Session restore
    @State private var restoreRecorderName: String?
    @State private var restoreTab: ConfigTab?
    @State private var restoreChannelName: String?

    init() {
        _service = StateObject(wrappedValue: ConfigService())
        if let saved = LastSessionStore.load() {
            _restoreRecorderName = State(initialValue: saved.configRecorderName)
            if let tabStr = saved.configTab, let tab = ConfigTab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
            _restoreChannelName = State(initialValue: saved.configDeliveryChannelName)
        }
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 310, idealWidth: 310, maxWidth: 350)

            Group {
                if tab == .recorders {
                    if let recorder = activeRecorder {
                        ConfigRecorderDetailView(
                            service: service,
                            recorder: recorder
                        )
                    } else {
                        EmptyDetailView(icon: "gearshape.2", message: "Select a recorder")
                    }
                } else {
                    if let channel = activeChannel {
                        ConfigDeliveryChannelDetailView(channel: channel)
                    } else {
                        EmptyDetailView(icon: "tray.and.arrow.down", message: "Select a delivery channel")
                    }
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
        }
        .toolbar {
            ConfigToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                tab: tab,
                hasRecorder: activeRecorder != nil,
                hasChannel: activeChannel != nil
            )
        }
        .onChange(of: tab) {
            if tab == .recorders {
                selectedChannelIDs = []
                activeChannel = nil
            } else {
                selectedRecorderIDs = []
                activeRecorder = nil
            }
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeRecorder) {
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeChannel) {
            toolbarState.reset()
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
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
            case .recorders:
                ConfigRecorderListView(
                    service: service,
                    toolbarState: toolbarState,
                    selectedRecorderIDs: $selectedRecorderIDs,
                    activeRecorder: $activeRecorder,
                    restoreRecorderName: restoreRecorderName
                )
            case .deliveryChannels:
                ConfigDeliveryChannelListView(
                    service: service,
                    toolbarState: toolbarState,
                    selectedChannelIDs: $selectedChannelIDs,
                    activeChannel: $activeChannel,
                    restoreChannelName: restoreChannelName
                )
            }
        }
    }

    private var listHeader: some View {
        ListHeaderBar(
            title: "Config",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: configDeleteDisabled,
            onRefresh: {},
            onCreate: { toolbarState.pendingAction = tab == .recorders ? .createRecorder : .createChannel },
            onDelete: { toolbarState.pendingAction = tab == .recorders ? .deleteRecorder : .deleteChannel }
        )
    }

    private var configDeleteDisabled: Bool {
        let hasSelection = tab == .recorders ? activeRecorder != nil : activeChannel != nil
        return !hasSelection || appState.isReadOnly
    }


    // MARK: - Session

    private func saveSession() {
        LastSessionStore.saveConfig(
            tab: tab.rawValue,
            recorderName: activeRecorder?.name,
            deliveryChannelName: activeChannel?.name
        )
    }
}

struct ConfigModule: ServiceModule {
    let serviceName = "Config"
    let serviceIcon = "gearshape.2"
    let serviceEndpoint = "/config"

    func makeMainView() -> AnyView {
        AnyView(ConfigModuleView())
    }
}
