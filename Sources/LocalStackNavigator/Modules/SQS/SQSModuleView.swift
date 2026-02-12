import SwiftUI

struct SQSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SQSService
    @StateObject private var toolbarState = SQSToolbarState()
    @StateObject private var favoriteStore = SQSFavoriteStore()

    @State private var selectedQueueIDs: Set<SQSQueue.ID> = []
    @State private var activeQueue: SQSQueue?

    init() {
        _service = StateObject(wrappedValue: SQSService(client: LocalStackClient(appState: AppState())))
    }

    var body: some View {
        HSplitView {
            SQSQueueListView(
                service: service,
                selectedQueueIDs: $selectedQueueIDs,
                activeQueue: $activeQueue
            )
            .frame(width: 260)

            Group {
                if let queue = activeQueue {
                    SQSMessageBrowserView(
                        service: service,
                        queue: queue,
                        toolbarState: toolbarState,
                        favoriteStore: favoriteStore
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.2")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a queue")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            SQSToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasQueue: activeQueue != nil
            )
        }
        .onChange(of: activeQueue) {
            toolbarState.reset()
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SQSModule: LocalStackModule {
    let serviceName = "SQS"
    let serviceIcon = "tray.2"
    let serviceEndpoint = "/sqs"

    func makeMainView() -> AnyView {
        AnyView(SQSModuleView())
    }
}
