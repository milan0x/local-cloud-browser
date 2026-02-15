import SwiftUI

struct KinesisModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: KinesisService
    @StateObject private var firehoseService: KinesisFirehoseService
    @StateObject private var toolbarState = KinesisToolbarState()

    @State private var tab: KinesisTab = .streams

    // Streams selection
    @State private var selectedStreamIDs: Set<KinesisStreamSummary.ID> = []
    @State private var activeStream: KinesisStreamSummary?

    // Firehose selection
    @State private var selectedDeliveryStreamIDs: Set<FirehoseDeliveryStreamSummary.ID> = []
    @State private var activeDeliveryStream: FirehoseDeliveryStreamSummary?

    // Session restore
    @State private var restoreStreamName: String?
    @State private var restoreTab: KinesisTab?
    @State private var restoreDeliveryStreamName: String?

    init() {
        _service = StateObject(wrappedValue: KinesisService())
        _firehoseService = StateObject(wrappedValue: KinesisFirehoseService())
        if let saved = LastSessionStore.load() {
            _restoreStreamName = State(initialValue: saved.kinesisStreamName)
            if let tabStr = saved.kinesisTab, let tab = KinesisTab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
            _restoreDeliveryStreamName = State(initialValue: saved.kinesisFirehoseDeliveryStreamName)
        }
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(width: 260)

            Group {
                if tab == .streams {
                    if let stream = activeStream {
                        KinesisStreamDetailPaneView(
                            service: service,
                            streamName: stream.streamName
                        )
                    } else {
                        emptyDetail("Select a stream", icon: "arrow.right.arrow.left.square")
                    }
                } else {
                    if let stream = activeDeliveryStream {
                        KinesisFirehoseDetailView(
                            service: firehoseService,
                            deliveryStreamName: stream.deliveryStreamName
                        )
                    } else {
                        emptyDetail("Select a delivery stream", icon: "flame")
                    }
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            KinesisToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                tab: tab,
                hasStream: activeStream != nil,
                hasDeliveryStream: activeDeliveryStream != nil
            )
        }
        .onChange(of: tab) {
            if tab == .streams {
                selectedDeliveryStreamIDs = []
                activeDeliveryStream = nil
            } else {
                selectedStreamIDs = []
                activeStream = nil
            }
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeStream) {
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeDeliveryStream) {
            toolbarState.reset()
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
            firehoseService.updateClient(client)
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

            Picker("Tab", selection: $tab) {
                ForEach(KinesisTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            switch tab {
            case .streams:
                KinesisStreamListView(
                    service: service,
                    toolbarState: toolbarState,
                    selectedStreamIDs: $selectedStreamIDs,
                    activeStream: $activeStream,
                    restoreStreamName: restoreStreamName
                )
            case .firehose:
                KinesisFirehoseListView(
                    service: firehoseService,
                    toolbarState: toolbarState,
                    selectedStreamIDs: $selectedDeliveryStreamIDs,
                    activeStream: $activeDeliveryStream,
                    restoreDeliveryStreamName: restoreDeliveryStreamName
                )
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("Kinesis")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {}

            Spacer()

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {}
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        LastSessionStore.saveKinesis(
            tab: tab.rawValue,
            streamName: activeStream?.streamName,
            deliveryStreamName: activeDeliveryStream?.deliveryStreamName
        )
    }
}

struct KinesisModule: LocalStackModule {
    let serviceName = "Kinesis"
    let serviceIcon = "arrow.right.arrow.left.square"
    let serviceEndpoint = "/kinesis"

    func makeMainView() -> AnyView {
        AnyView(KinesisModuleView())
    }
}
