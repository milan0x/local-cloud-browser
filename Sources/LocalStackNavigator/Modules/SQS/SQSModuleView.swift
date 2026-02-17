import SwiftUI

struct SQSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SQSService
    @StateObject private var toolbarState = SQSToolbarState()
    @StateObject private var favoriteStore = SQSFavoriteStore()

    @State private var selectedQueueIDs: Set<SQSQueue.ID> = []
    @State private var activeQueue: SQSQueue?

    // Pane focus
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var listPaneFocusTrigger = 0
    @State private var detailPaneFocusTrigger = 0

    // Session restore: captured once when the view is created
    @State private var restoreQueueName: String?

    init() {
        _service = StateObject(wrappedValue: SQSService())
        if let saved = LastSessionStore.load() {
            _restoreQueueName = State(initialValue: saved.sqsQueueName)
        }
    }

    var body: some View {
        HSplitView {
            SQSQueueListView(
                service: service,
                selectedQueueIDs: $selectedQueueIDs,
                activeQueue: $activeQueue,
                restoreQueueName: restoreQueueName,
                searchFocusTrigger: listSearchFocusTrigger,
                paneFocusTrigger: listPaneFocusTrigger
            )
            .frame(width: 280)
            .onKeyPress(.rightArrow) {
                guard activeQueue != nil else { return .ignored }
                detailPaneFocusTrigger += 1
                return .handled
            }

            Group {
                if let queue = activeQueue {
                    SQSMessageBrowserView(
                        service: service,
                        queue: queue,
                        toolbarState: toolbarState,
                        favoriteStore: favoriteStore,
                        searchFocusTrigger: detailSearchFocusTrigger,
                        paneFocusTrigger: detailPaneFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "tray.2", message: "Select a queue")
                }
            }
            .frame(minWidth: 400)
            .onKeyPress(.leftArrow) {
                listPaneFocusTrigger += 1
                return .handled
            }
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
            LastSessionStore.saveSQSQueue(activeQueue?.queueName)
        }
        .cmdFSearchCycling(
            hasDetail: activeQueue != nil,
            activeItemID: activeQueue?.id,
            listSearchFocusTrigger: $listSearchFocusTrigger,
            detailSearchFocusTrigger: $detailSearchFocusTrigger
        )
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
