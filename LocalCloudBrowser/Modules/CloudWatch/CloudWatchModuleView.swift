import SwiftUI

struct CloudWatchModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: CloudWatchService
    @StateObject private var toolbarState = CloudWatchToolbarState()

    @State private var tab: CloudWatchTab = .metrics
    @State private var activeMetric: CloudWatchMetric?
    @State private var activeAlarm: CloudWatchAlarm?

    // Session restore
    @State private var restoreTab: CloudWatchTab?
    @State private var restoreAlarmName: String?

    init() {
        _service = StateObject(wrappedValue: CloudWatchService())
        if let saved = LastSessionStore.load() {
            if let tabStr = saved.cloudWatchTab, let tab = CloudWatchTab(rawValue: tabStr) {
                _restoreTab = State(initialValue: tab)
            }
            _restoreAlarmName = State(initialValue: saved.cloudWatchAlarmName)
        }
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 310, idealWidth: 310, maxWidth: 350)

            Group {
                if tab == .metrics, let metric = activeMetric {
                    CloudWatchMetricChartView(
                        service: service,
                        metric: metric
                    )
                } else if tab == .alarms, let alarm = activeAlarm {
                    CloudWatchAlarmDetailView(alarm: alarm)
                } else {
                    EmptyDetailView(icon: "chart.xyaxis.line", message: tab == .metrics ? "Select a metric" : "Select an alarm")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
        }
        .toolbar {
            CloudWatchToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                tab: tab,
                hasAlarmSelection: activeAlarm != nil
            )
        }
        .onChange(of: tab) {
            // Clear opposite selection on tab switch
            if tab == .metrics {
                activeAlarm = nil
            } else {
                activeMetric = nil
            }
            saveSession()
        }
        .onChange(of: activeAlarm) {
            toolbarState.reset()
            saveSession()
        }
        .onChange(of: activeMetric) {
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
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
            case .metrics:
                CloudWatchMetricListView(
                    service: service,
                    toolbarState: toolbarState,
                    activeMetric: $activeMetric
                )
            case .alarms:
                CloudWatchAlarmListView(
                    service: service,
                    toolbarState: toolbarState,
                    activeAlarm: $activeAlarm,
                    restoreAlarmName: restoreAlarmName
                )
            }
        }
    }

    private var listHeader: some View {
        ListHeaderBar(
            title: "CloudWatch",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: cwDeleteDisabled,
            onRefresh: {},
            onCreate: { toolbarState.pendingAction = tab == .metrics ? .putMetric : .createAlarm },
            onDelete: { toolbarState.pendingAction = .deleteAlarm }
        )
    }

    private var cwDeleteDisabled: Bool {
        tab != .alarms || activeAlarm == nil || appState.isReadOnly
    }

    // MARK: - Session

    private func saveSession() {
        LastSessionStore.saveCloudWatch(
            tab: tab.rawValue,
            alarmName: activeAlarm?.alarmName
        )
    }
}

struct CloudWatchModule: ServiceModule {
    let serviceName = "CloudWatch"
    let serviceIcon = "chart.xyaxis.line"
    let serviceEndpoint = "/cloudwatch"

    func makeMainView() -> AnyView {
        AnyView(CloudWatchModuleView())
    }
}
