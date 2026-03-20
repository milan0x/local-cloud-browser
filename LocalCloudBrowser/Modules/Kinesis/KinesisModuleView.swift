import SwiftUI

struct KinesisModuleView: View {
    @EnvironmentObject private var client: CloudClient
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
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 450)

            Group {
                if tab == .streams {
                    if let stream = activeStream {
                        KinesisStreamDetailPaneView(
                            service: service,
                            streamName: stream.streamName
                        )
                    } else {
                        EmptyDetailView(icon: "arrow.right.arrow.left.square", message: "Select a stream")
                    }
                } else {
                    if let stream = activeDeliveryStream {
                        KinesisFirehoseDetailView(
                            service: firehoseService,
                            deliveryStreamName: stream.deliveryStreamName
                        )
                    } else {
                        EmptyDetailView(icon: "flame", message: "Select a delivery stream")
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

            SegmentedTabPicker(selection: $tab)

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
        ListHeaderBar(
            title: "Kinesis",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: kinesisDeleteDisabled,
            onRefresh: {},
            onCreate: { toolbarState.pendingAction = tab == .streams ? .createStream : .createDeliveryStream },
            onDelete: { toolbarState.pendingAction = tab == .streams ? .deleteStream : .deleteDeliveryStream }
        )
    }

    private var kinesisDeleteDisabled: Bool {
        let hasSelection = tab == .streams ? activeStream != nil : activeDeliveryStream != nil
        return !hasSelection || appState.isReadOnly
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

struct KinesisModule: ServiceModule {
    let serviceName = "Kinesis"
    let serviceIcon = "arrow.right.arrow.left.square"
    let serviceEndpoint = "/kinesis"

    func makeMainView() -> AnyView {
        AnyView(KinesisModuleView())
    }
}
