import SwiftUI

struct CloudWatchModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
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
                .frame(width: 260)

            Group {
                if tab == .metrics, let metric = activeMetric {
                    CloudWatchMetricChartView(
                        service: service,
                        metric: metric
                    )
                } else if tab == .alarms, let alarm = activeAlarm {
                    CloudWatchAlarmDetailView(alarm: alarm)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(tab == .metrics ? "Select a metric" : "Select an alarm")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
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

            Picker("Tab", selection: $tab) {
                ForEach(CloudWatchTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

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
        HStack {
            Text("CloudWatch")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {}

            Spacer()

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {}
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Session

    private func saveSession() {
        LastSessionStore.saveCloudWatch(
            tab: tab.rawValue,
            alarmName: activeAlarm?.alarmName
        )
    }
}

struct CloudWatchModule: LocalStackModule {
    let serviceName = "CloudWatch"
    let serviceIcon = "chart.xyaxis.line"
    let serviceEndpoint = "/cloudwatch"

    func makeMainView() -> AnyView {
        AnyView(CloudWatchModuleView())
    }
}
