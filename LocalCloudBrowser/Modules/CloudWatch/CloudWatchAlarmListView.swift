import SwiftUI
import AppKit

struct CloudWatchAlarmListView: View {
    @ObservedObject var service: CloudWatchService
    @ObservedObject var toolbarState: CloudWatchToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var activeAlarm: CloudWatchAlarm?
    var restoreAlarmName: String?

    @State private var selectedAlarmIDs: Set<CloudWatchAlarm.ID> = []
    @State private var searchText = ""
    @State private var serviceError: ServiceError?
    @State private var showCreateAlarmSheet = false
    @State private var alarmsToDelete: [CloudWatchAlarm] = []
    @State private var pendingSelectName: String?
    @State private var showSetStateSheet = false
    @StateObject private var loader = PaginatedListLoader<CloudWatchAlarm>()
    private var alarms: [CloudWatchAlarm] { loader.items }

    var body: some View {
        listContent
        .sheet(isPresented: $showCreateAlarmSheet) {
            CloudWatchCreateAlarmView(service: service, existingAlarmNames: Set(alarms.map(\.alarmName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadAlarms(force: true) }
        }
        .sheet(isPresented: $showSetStateSheet) {
            if let alarm = activeAlarm {
                CloudWatchSetAlarmStateView(service: service, alarm: alarm)
                    .onDisappear { loadAlarms(force: true) }
            }
        }
        .deleteConfirmation(items: $alarmsToDelete, noun: "Alarm") { items in
            if items.count == 1, let alarm = items.first {
                Text("Are you sure you want to delete alarm \"\(alarm.alarmName)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) alarms?")
            }
        } onDelete: { deleteAlarms($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadAlarms() }
        .onAutoRefresh(canRefresh: { !showCreateAlarmSheet && !showSetStateSheet && alarmsToDelete.isEmpty && !loader.isLoading }) {
            loadAlarms(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedAlarmIDs = []
            activeAlarm = nil
            loader.items = []
            loadAlarms(force: true)
        }
        .syncSelection(selectedAlarmIDs, items: alarms, activeItem: $activeAlarm)
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

    private var listContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: alarms.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading alarms...", emptyIcon: "bell", emptyMessage: "No alarms", onRetry: { loadAlarms(force: true) }) {
            VStack(spacing: 0) {
                if alarms.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter alarms")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedAlarmIDs) {
                    ForEach(filteredAlarms) { alarm in
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
                    .selectionForeground()
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
                }
                .contextMenu {
                    Button("Create Alarm") { showCreateAlarmSheet = true }
                        .disabled(appState.isReadOnly)
                }

                if loader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            loader.loadMore()
                        } label: {
                            if loader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(loader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredAlarms.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.alarmName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if loader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if loader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                ListStatusBar(totalCount: alarms.count, selectedCount: selectedAlarmIDs.count, noun: "alarm", hasMorePages: loader.hasMorePages)
            }
        }
    }

    private func alarmStateBadge(_ state: CloudWatchAlarmState) -> some View {
        StatusBadge(text: state.displayName, color: state.color)
    }

    // MARK: - Data

    private func loadAlarms(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.describeAlarmsPage(token: token) },
            sort: { $0.alarmName.localizedStandardCompare($1.alarmName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreAlarmName,
               let alarm = items.first(where: { $0.alarmName == savedName }) {
                selectedAlarmIDs = [alarm.id]
                activeAlarm = alarm
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let alarm = items.first(where: { $0.alarmName == name }) {
                selectedAlarmIDs = [alarm.id]
                activeAlarm = alarm
                pendingSelectName = nil
            }
        }
    }

    private func deleteAlarms(_ targets: [CloudWatchAlarm]) {
        Task {
            selectedAlarmIDs.subtract(Set(targets.map(\.id)))
            do {
                try await service.deleteAlarms(names: targets.map(\.alarmName))
                let deletedIDs = Set(targets.map(\.id))
                licenseManager.decrementCreateCount(for: .cloudWatch, by: deletedIDs.count)
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
