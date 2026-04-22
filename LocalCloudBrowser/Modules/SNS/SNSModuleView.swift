import SwiftUI

struct SNSModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SNSService
    @StateObject private var toolbarState = SNSToolbarState()

    @State private var selectedTopicIDs: Set<SNSTopic.ID> = []
    @State private var activeTopic: SNSTopic?

    // Pane focus
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var listPaneFocusTrigger = 0
    @State private var detailPaneFocusTrigger = 0

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
                searchFocusTrigger: listSearchFocusTrigger,
                paneFocusTrigger: listPaneFocusTrigger
            )
            .frame(minWidth: 260, idealWidth: 290, maxWidth: 350)
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                appState.sidebarFocusTrigger += 1
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                guard activeTopic != nil else { return .ignored }
                detailPaneFocusTrigger += 1
                return .handled
            }

            Group {
                if let topic = activeTopic {
                    SNSSubscriptionListView(
                        service: service,
                        topic: topic,
                        toolbarState: toolbarState,
                        searchFocusTrigger: detailSearchFocusTrigger,
                        paneFocusTrigger: detailPaneFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "bell", message: "Select a topic")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                listPaneFocusTrigger += 1
                return .handled
            }
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
        }
        .cmdFSearchCycling(
            hasDetail: activeTopic != nil,
            activeItemID: activeTopic?.id,
            listSearchFocusTrigger: $listSearchFocusTrigger,
            detailSearchFocusTrigger: $detailSearchFocusTrigger
        )
        .onChange(of: appState.moduleListFocusTrigger) {
            listPaneFocusTrigger += 1
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SNSModule: ServiceModule {
    let serviceName = "SNS"
    let serviceIcon = "bell"
    let serviceEndpoint = "/sns"

    func makeMainView() -> AnyView {
        AnyView(SNSModuleView())
    }
}
