import SwiftUI

struct ConfigModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
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
                .frame(width: 280)

            Group {
                if tab == .recorders {
                    if let recorder = activeRecorder {
                        ConfigRecorderDetailView(
                            service: service,
                            recorder: recorder
                        )
                    } else {
                        emptyDetail("Select a recorder", icon: "gearshape.2")
                    }
                } else {
                    if let channel = activeChannel {
                        ConfigDeliveryChannelDetailView(channel: channel)
                    } else {
                        emptyDetail("Select a delivery channel", icon: "tray.and.arrow.down")
                    }
                }
            }
            .frame(minWidth: 400)
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
        HStack {
            Text("Config")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {}

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                toolbarState.pendingAction = tab == .recorders ? .createRecorder : .createChannel
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {}

            ListHeaderButton("trash", color: .red, isDisabled: configDeleteDisabled) {
                toolbarState.pendingAction = tab == .recorders ? .deleteRecorder : .deleteChannel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var configDeleteDisabled: Bool {
        let hasSelection = tab == .recorders ? activeRecorder != nil : activeChannel != nil
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
        LastSessionStore.saveConfig(
            tab: tab.rawValue,
            recorderName: activeRecorder?.name,
            deliveryChannelName: activeChannel?.name
        )
    }
}

struct ConfigModule: LocalStackModule {
    let serviceName = "Config"
    let serviceIcon = "gearshape.2"
    let serviceEndpoint = "/config"

    func makeMainView() -> AnyView {
        AnyView(ConfigModuleView())
    }
}
