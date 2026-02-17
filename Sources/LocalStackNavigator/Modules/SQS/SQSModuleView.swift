import SwiftUI

struct SQSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SQSService
    @StateObject private var toolbarState = SQSToolbarState()
    @StateObject private var favoriteStore = SQSFavoriteStore()

    @State private var selectedQueueIDs: Set<SQSQueue.ID> = []
    @State private var activeQueue: SQSQueue?

    // Cmd+F search focus cycling
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var lastSearchTarget = SearchTarget.detail

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
                searchFocusTrigger: listSearchFocusTrigger
            )
            .frame(width: 280)

            Group {
                if let queue = activeQueue {
                    SQSMessageBrowserView(
                        service: service,
                        queue: queue,
                        toolbarState: toolbarState,
                        favoriteStore: favoriteStore,
                        searchFocusTrigger: detailSearchFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "tray.2", message: "Select a queue")
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
            LastSessionStore.saveSQSQueue(activeQueue?.queueName)
            lastSearchTarget = .detail
        }
        .background {
            Button("") { cycleCmdF() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func cycleCmdF() {
        if activeQueue != nil, lastSearchTarget != .detail {
            detailSearchFocusTrigger += 1
            lastSearchTarget = .detail
        } else if activeQueue != nil {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        } else {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        }
    }
}

private enum SearchTarget {
    case detail, list
}

struct SQSModule: LocalStackModule {
    let serviceName = "SQS"
    let serviceIcon = "tray.2"
    let serviceEndpoint = "/sqs"

    func makeMainView() -> AnyView {
        AnyView(SQSModuleView())
    }
}
