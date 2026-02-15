import SwiftUI
import AppKit

struct EventBridgeScheduleGroupListView: View {
    @ObservedObject var service: EventBridgeSchedulerService
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedGroupIDs: Set<SchedulerScheduleGroup.ID>
    @Binding var activeGroup: SchedulerScheduleGroup?
    var restoreGroupName: String?

    @State private var groups: [SchedulerScheduleGroup] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var groupsToDelete: [SchedulerScheduleGroup] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            groupListHeader
            Divider()
            groupListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            EventBridgeCreateScheduleGroupView(service: service, existingGroupNames: Set(groups.map(\.name)))
                .onDisappear { loadGroups(force: true) }
        }
        .alert(
            groupsToDelete.count == 1
                ? "Delete Schedule Group"
                : "Delete \(groupsToDelete.count) Schedule Groups",
            isPresented: Binding(
                get: { !groupsToDelete.isEmpty },
                set: { if !$0 { groupsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteGroups(groupsToDelete)
            }
            Button("Cancel", role: .cancel) {
                groupsToDelete = []
            }
        } message: {
            if groupsToDelete.count == 1, let group = groupsToDelete.first {
                Text("Are you sure you want to delete \"\(group.name)\"?\n\nAll schedules in this group will be permanently deleted.")
            } else {
                let names = groupsToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these schedule groups?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadGroups() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && groupsToDelete.isEmpty && !isLoading }) {
            loadGroups(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedGroupIDs = []
            activeGroup = nil
            groups = []
            loadGroups(force: true)
        }
        .onChange(of: selectedGroupIDs) {
            if selectedGroupIDs.count == 1, let id = selectedGroupIDs.first {
                activeGroup = groups.first { $0.id == id }
            } else {
                activeGroup = nil
            }
        }
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
        HStack {
            Text("Schedule Groups")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadGroups(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadGroups(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: groupDeleteDisabled, help: selectedGroupIDs.count <= 1 ? "Delete Schedule Group" : "Delete \(selectedGroupIDs.count) Schedule Groups") {
                let deletable = groups.filter { selectedGroupIDs.contains($0.id) && !$0.isDefault }
                if !deletable.isEmpty {
                    groupsToDelete = deletable
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var groupListContent: some View {
        if isLoading && groups.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading schedule groups...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, groups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadGroups(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if groups.isEmpty {
            EmptyStateView(icon: "calendar.badge.clock", message: "No schedule groups")
            .contextMenu {
                Button("Create Schedule Group") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if groups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter schedule groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredGroups, selection: $selectedGroupIDs) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if group.isDefault {
                            StatusBadge(text: "default", color: .blue)
                        }
                    }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Schedule Group") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(groups.count) group\(groups.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedGroupIDs.count > 1 {
                        Text("(\(selectedGroupIDs.count) selected)")
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

    private var connectionLostBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost — showing cached data")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
    }

    // MARK: - Data

    private func loadGroups(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listScheduleGroups()
                let freshGroups = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if groups != freshGroups {
                    groups = freshGroups
                }
                if !hasRestoredSession, let savedName = restoreGroupName,
                   let group = groups.first(where: { $0.name == savedName }) {
                    selectedGroupIDs = [group.id]
                    activeGroup = group
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

    private func deleteGroups(_ targets: [SchedulerScheduleGroup]) {
        Task {
            var deletedIDs: Set<SchedulerScheduleGroup.ID> = []
            for group in targets {
                guard !group.isDefault else { continue }
                do {
                    try await service.deleteScheduleGroup(name: group.name)
                    deletedIDs.insert(group.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedGroupIDs.subtract(deletedIDs)
                if let active = activeGroup, deletedIDs.contains(active.id) {
                    activeGroup = nil
                }
                loadGroups(force: true)
            }
        }
    }
}
