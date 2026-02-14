import SwiftUI

struct CloudWatchLogsModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: CloudWatchLogsService
    @StateObject private var toolbarState = CloudWatchLogsToolbarState()

    @State private var selectedLogGroupIDs: Set<CloudWatchLogGroup.ID> = []
    @State private var activeLogGroup: CloudWatchLogGroup?

    // Session restore: captured once when the view is created
    @State private var restoreLogGroupName: String?

    init() {
        _service = StateObject(wrappedValue: CloudWatchLogsService())
        if let saved = LastSessionStore.load() {
            _restoreLogGroupName = State(initialValue: saved.cloudWatchLogsLogGroupName)
        }
    }

    var body: some View {
        HSplitView {
            CloudWatchLogsGroupListView(
                service: service,
                toolbarState: toolbarState,
                selectedLogGroupIDs: $selectedLogGroupIDs,
                activeLogGroup: $activeLogGroup,
                restoreLogGroupName: restoreLogGroupName
            )
            .frame(width: 260)

            Group {
                if let logGroup = activeLogGroup {
                    CloudWatchLogsStreamBrowserView(
                        service: service,
                        logGroup: logGroup,
                        toolbarState: toolbarState
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a log group")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            CloudWatchLogsToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasLogGroup: activeLogGroup != nil
            )
        }
        .onChange(of: activeLogGroup) {
            toolbarState.reset()
            LastSessionStore.saveCloudWatchLogsLogGroup(activeLogGroup?.logGroupName)
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct CloudWatchLogsModule: LocalStackModule {
    let serviceName = "CloudWatch Logs"
    let serviceIcon = "doc.text.magnifyingglass"
    let serviceEndpoint = "/logs"

    func makeMainView() -> AnyView {
        AnyView(CloudWatchLogsModuleView())
    }
}
