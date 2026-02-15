import SwiftUI

struct KinesisModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: KinesisService
    @StateObject private var toolbarState = KinesisToolbarState()

    @State private var selectedStreamIDs: Set<KinesisStreamSummary.ID> = []
    @State private var activeStream: KinesisStreamSummary?

    // Session restore: captured once when the view is created
    @State private var restoreStreamName: String?

    init() {
        _service = StateObject(wrappedValue: KinesisService())
        if let saved = LastSessionStore.load() {
            _restoreStreamName = State(initialValue: saved.kinesisStreamName)
        }
    }

    var body: some View {
        HSplitView {
            KinesisStreamListView(
                service: service,
                toolbarState: toolbarState,
                selectedStreamIDs: $selectedStreamIDs,
                activeStream: $activeStream,
                restoreStreamName: restoreStreamName
            )
            .frame(width: 260)

            Group {
                if let stream = activeStream {
                    KinesisStreamDetailPaneView(
                        service: service,
                        streamName: stream.streamName
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right.arrow.left.square")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a stream")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            KinesisToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasStream: activeStream != nil
            )
        }
        .onChange(of: activeStream) {
            toolbarState.reset()
            LastSessionStore.saveKinesisStream(activeStream?.streamName)
        }
        .onAppear {
            service.updateClient(client)
        }
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
