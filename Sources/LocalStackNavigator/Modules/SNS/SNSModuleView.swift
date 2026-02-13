import SwiftUI

struct SNSModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: SNSService
    @StateObject private var toolbarState = SNSToolbarState()

    @State private var selectedTopicIDs: Set<SNSTopic.ID> = []
    @State private var activeTopic: SNSTopic?

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
                restoreTopicArn: restoreTopicArn
            )
            .frame(width: 260)

            Group {
                if let topic = activeTopic {
                    SNSSubscriptionListView(
                        service: service,
                        topic: topic,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "bell")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a topic")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct SNSModule: LocalStackModule {
    let serviceName = "SNS"
    let serviceIcon = "bell"
    let serviceEndpoint = "/sns"

    func makeMainView() -> AnyView {
        AnyView(SNSModuleView())
    }
}
