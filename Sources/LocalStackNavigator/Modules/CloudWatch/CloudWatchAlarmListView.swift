import SwiftUI
import AppKit

struct CloudWatchAlarmListView: View {
    @ObservedObject var service: CloudWatchService
    @ObservedObject var toolbarState: CloudWatchToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var activeAlarm: CloudWatchAlarm?
    var restoreAlarmName: String?

    @State private var alarms: [CloudWatchAlarm] = []
    @State private var selectedAlarmIDs: Set<CloudWatchAlarm.ID> = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""
    @State private var serviceError: ServiceError?
    @State private var showCreateAlarmSheet = false
    @State private var alarmsToDelete: [CloudWatchAlarm] = []
    @State private var showSetStateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            listContent
        }
        .sheet(isPresented: $showCreateAlarmSheet) {
            CloudWatchCreateAlarmView(service: service, existingAlarmNames: Set(alarms.map(\.alarmName)))
                .onDisappear { loadAlarms(force: true) }
        }
        .sheet(isPresented: $showSetStateSheet) {
            if let alarm = activeAlarm {
                CloudWatchSetAlarmStateView(service: service, alarm: alarm)
                    .onDisappear { loadAlarms(force: true) }
            }
        }
        .alert(
            alarmsToDelete.count == 1
                ? "Delete Alarm"
                : "Delete \(alarmsToDelete.count) Alarms",
            isPresented: Binding(
                get: { !alarmsToDelete.isEmpty },
                set: { if !$0 { alarmsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) { deleteAlarms(alarmsToDelete) }
            Button("Cancel", role: .cancel) { alarmsToDelete = [] }
        } message: {
            if alarmsToDelete.count == 1, let alarm = alarmsToDelete.first {
                Text("Are you sure you want to delete alarm \"\(alarm.alarmName)\"?")
            } else {
                Text("Are you sure you want to delete \(alarmsToDelete.count) alarms?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadAlarms() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateAlarmSheet && !showSetStateSheet && alarmsToDelete.isEmpty && !isLoading else { return }
            loadAlarms(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedAlarmIDs = []
            activeAlarm = nil
            alarms = []
            loadAlarms(force: true)
        }
        .onChange(of: appState.region) {
            selectedAlarmIDs = []
            activeAlarm = nil
            alarms = []
            loadAlarms(force: true)
        }
        .onChange(of: selectedAlarmIDs) {
            if selectedAlarmIDs.count == 1, let id = selectedAlarmIDs.first {
                activeAlarm = alarms.first { $0.id == id }
            } else {
                activeAlarm = nil
            }
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createAlarm:
                toolbarState.pendingAction = nil
                showCreateAlarmSheet = true
            case .deleteAlarm:
                toolbarState.pendingAction = nil
                if let active = activeAlarm {
                    alarmsToDelete = [active]
                }
            case .setAlarmState:
                toolbarState.pendingAction = nil
                if activeAlarm != nil {
                    showSetStateSheet = true
                }
            case .putMetric:
                break // handled by metric list
            }
        }
    }

    // MARK: - Content

    private var filteredAlarms: [CloudWatchAlarm] {
        guard !searchText.isEmpty else { return alarms }
        let query = searchText.lowercased()
        return alarms.filter {
            $0.alarmName.lowercased().contains(query) ||
            $0.metricName.lowercased().contains(query) ||
            $0.namespace.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading && alarms.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading alarms...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, alarms.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadAlarms(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if alarms.isEmpty {
            EmptyStateView(icon: "bell", message: "No alarms")
            .contextMenu {
                Button("Create Alarm") { showCreateAlarmSheet = true }
                    .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if alarms.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter alarms")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredAlarms, selection: $selectedAlarmIDs) { alarm in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alarm.alarmName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(alarm.metricName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        alarmStateBadge(alarm.alarmState)
                    }
                    .tag(alarm.id)
                    .contextMenu {
                        Button("Copy Alarm Name") { copyToClipboard(alarm.alarmName) }
                        if !alarm.alarmArn.isEmpty {
                            Button("Copy ARN") { copyToClipboard(alarm.alarmArn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Alarm") {
                                copyToClipboard(alarm.describeAlarmCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Alarms") {
                                copyToClipboard(CloudWatchAlarm.listAlarmsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Set State...") {
                            selectedAlarmIDs = [alarm.id]
                            activeAlarm = alarm
                            showSetStateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Create Alarm") { showCreateAlarmSheet = true }
                            .disabled(appState.isReadOnly)
                        Divider()
                        if selectedAlarmIDs.count > 1 && selectedAlarmIDs.contains(alarm.id) {
                            let selected = alarms.filter { selectedAlarmIDs.contains($0.id) }
                            Button("Delete \(selected.count) Alarms", role: .destructive) {
                                alarmsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) { alarmsToDelete = [alarm] }
                                .disabled(appState.isReadOnly)
                        }
                    }
                }
                .contextMenu {
                    Button("Create Alarm") { showCreateAlarmSheet = true }
                        .disabled(appState.isReadOnly)
                }

                Divider()
                HStack {
                    Text("\(alarms.count) alarm\(alarms.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedAlarmIDs.count > 1 {
                        Text("(\(selectedAlarmIDs.count) selected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func alarmStateBadge(_ state: CloudWatchAlarmState) -> some View {
        Text(state.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(state.color.opacity(0.15), in: Capsule())
            .foregroundStyle(state.color)
    }

    // MARK: - Data

    private func loadAlarms(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.describeAlarms()
                let freshAlarms = loaded.sorted { $0.alarmName.localizedStandardCompare($1.alarmName) == .orderedAscending }
                if alarms != freshAlarms {
                    alarms = freshAlarms
                }
                if !hasRestoredSession, let savedName = restoreAlarmName,
                   let alarm = alarms.first(where: { $0.alarmName == savedName }) {
                    selectedAlarmIDs = [alarm.id]
                    activeAlarm = alarm
                }
                hasRestoredSession = true
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func deleteAlarms(_ targets: [CloudWatchAlarm]) {
        Task {
            do {
                try await service.deleteAlarms(names: targets.map(\.alarmName))
                let deletedIDs = Set(targets.map(\.id))
                selectedAlarmIDs.subtract(deletedIDs)
                if let active = activeAlarm, deletedIDs.contains(active.id) {
                    activeAlarm = nil
                }
                loadAlarms(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
