import SwiftUI
import AppKit

struct EventBridgeScheduleGroupListView: View {
    @ObservedObject var service: EventBridgeSchedulerService
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedGroupIDs: Set<SchedulerScheduleGroup.ID>
    @Binding var activeGroup: SchedulerScheduleGroup?
    var restoreGroupName: String?

    @State private var showCreateSheet = false
    @State private var groupsToDelete: [SchedulerScheduleGroup] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = ListLoader<SchedulerScheduleGroup>()
    private var groups: [SchedulerScheduleGroup] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            groupListHeader
            Divider()
            groupListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            EventBridgeCreateScheduleGroupView(service: service, existingGroupNames: Set(groups.map(\.name))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadGroups(force: true) }
        }
        .deleteConfirmation(items: $groupsToDelete, noun: "Schedule Group") { items in
            if items.count == 1, let group = items.first {
                Text("Are you sure you want to delete \"\(group.name)\"?\n\nAll schedules in this group will be permanently deleted.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these schedule groups?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteGroups($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadGroups() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && groupsToDelete.isEmpty && !loader.isLoading }) {
            loadGroups(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedGroupIDs = []
            activeGroup = nil
            loader.items = []
            loadGroups(force: true)
        }
        .syncSelection(selectedGroupIDs, items: groups, activeItem: $activeGroup)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .deleteSelectedGroup:
                toolbarState.pendingAction = nil
                if let active = activeGroup, !active.isDefault {
                    groupsToDelete = [active]
                }
            default:
                break
            }
        }
    }

    private var groupDeleteDisabled: Bool {
        appState.isReadOnly || selectedGroupIDs.isEmpty
    }

    private var filteredGroups: [SchedulerScheduleGroup] {
        guard !searchText.isEmpty else { return groups }
        let query = searchText.lowercased()
        return groups.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Header

    private var groupListHeader: some View {
        ListHeaderBar(
            title: "Schedule Groups",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: groupDeleteDisabled,
            deleteHelp: selectedGroupIDs.count <= 1 ? "Delete Schedule Group" : "Delete \(selectedGroupIDs.count) Schedule Groups",
            onRefresh: { loadGroups(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: {
                let deletable = groups.filter { selectedGroupIDs.contains($0.id) && !$0.isDefault }
                if !deletable.isEmpty { groupsToDelete = deletable }
            }
        )
    }

    // MARK: - Content

    private var groupListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: groups.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading schedule groups...", emptyIcon: "calendar.badge.clock", emptyMessage: "No schedule groups", onRetry: { loadGroups(force: true) }) {
            VStack(spacing: 0) {
                if groups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter schedule groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedGroupIDs) {
                    ForEach(filteredGroups) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if group.isDefault {
                            StatusBadge(text: "default", color: .blue)
                        }
                    }
                    .selectionForeground()
                    .tag(group.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(group.name) }
                        if let arn = group.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Divider()
                        Button("Create Schedule Group") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedGroupIDs.count > 1 && selectedGroupIDs.contains(group.id) {
                            let selected = groups.filter { selectedGroupIDs.contains($0.id) && !$0.isDefault }
                            Button("Delete \(selected.count) Schedule Groups", role: .destructive) {
                                groupsToDelete = selected
                            }
                            .disabled(appState.isReadOnly || selected.isEmpty)
                        } else {
                            Button("Delete", role: .destructive) {
                                groupsToDelete = [group]
                            }
                            .disabled(appState.isReadOnly || group.isDefault)
                        }
                    }
                    }
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Schedule Group") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: groups.count, selectedCount: selectedGroupIDs.count, noun: "schedule group")
            }
        }
    }

    // MARK: - Data

    private func loadGroups(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listScheduleGroups() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreGroupName,
               let group = items.first(where: { $0.name == savedName }) {
                selectedGroupIDs = [group.id]
                activeGroup = group
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let group = items.first(where: { $0.name == name }) {
                selectedGroupIDs = [group.id]
                activeGroup = group
                pendingSelectName = nil
            }
        }
    }

    private func deleteGroups(_ targets: [SchedulerScheduleGroup]) {
        let nonDefault = targets.filter { !$0.isDefault }
        Task {
            let (deletedIDs, lastError) = await batchDelete(nonDefault) { group in
                try await service.deleteScheduleGroup(name: group.name)
            }
            if let lastError { serviceError = lastError }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .eventBridge, by: deletedIDs.count)
                selectedGroupIDs.subtract(deletedIDs)
                if let active = activeGroup, deletedIDs.contains(active.id) {
                    activeGroup = nil
                }
                loadGroups(force: true)
            }
        }
    }
}
