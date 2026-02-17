import SwiftUI

struct SNSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SNSService
    @StateObject private var toolbarState = SNSToolbarState()

    @State private var selectedTopicIDs: Set<SNSTopic.ID> = []
    @State private var activeTopic: SNSTopic?

    // Cmd+F search focus cycling
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var lastSearchTarget = SearchTarget.detail

    // Session restore: captured once when the view is created
    @State private var restoreTopicArn: String?

    init() {
        _service = StateObject(wrappedValue: SNSService())
        if let saved = LastSessionStore.load() {
            _restoreTopicArn = State(initialValue: saved.snsTopicArn)
        }
    }

    var body: some View {
        HSplitView {
            SNSTopicListView(
                service: service,
                selectedTopicIDs: $selectedTopicIDs,
                activeTopic: $activeTopic,
                restoreTopicArn: restoreTopicArn,
                searchFocusTrigger: listSearchFocusTrigger
            )
            .frame(width: 280)

            Group {
                if let topic = activeTopic {
                    SNSSubscriptionListView(
                        service: service,
                        topic: topic,
                        toolbarState: toolbarState,
                        searchFocusTrigger: detailSearchFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "bell", message: "Select a topic")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            SNSToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasTopic: activeTopic != nil
            )
        }
        .onChange(of: activeTopic) {
            toolbarState.reset()
            LastSessionStore.saveSNSTopic(activeTopic?.topicArn)
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
        if activeTopic != nil, lastSearchTarget != .detail {
            detailSearchFocusTrigger += 1
            lastSearchTarget = .detail
        } else if activeTopic != nil {
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

struct SNSModule: LocalStackModule {
    let serviceName = "SNS"
    let serviceIcon = "bell"
    let serviceEndpoint = "/sns"

    func makeMainView() -> AnyView {
        AnyView(SNSModuleView())
    }
}
