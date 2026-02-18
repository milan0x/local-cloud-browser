import SwiftUI
import AppKit

struct ResourceGroupsListView: View {
    @ObservedObject var service: ResourceGroupsService
    @ObservedObject var toolbarState: ResourceGroupsToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedGroupIDs: Set<ResourceGroupSummary.ID>
    @Binding var activeGroup: ResourceGroupSummary?
    var restoreGroupName: String?

    @StateObject private var loader = ListLoader<ResourceGroupSummary>()
    private var groups: [ResourceGroupSummary] { loader.items }
    @State private var showCreateSheet = false
    @State private var groupsToDelete: [ResourceGroupSummary] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            listContent
        }
        .sheet(isPresented: $showCreateSheet) {
            ResourceGroupsCreateView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadGroups(force: true) }
        }
        .deleteConfirmation(items: $groupsToDelete, noun: "Resource Group") { items in
            if items.count == 1, let group = items.first {
                Text("Are you sure you want to delete the resource group \"\(group.name)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) resource groups?")
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
            case .createGroup:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteGroup:
                toolbarState.pendingAction = nil
                if let active = activeGroup {
                    groupsToDelete = [active]
                }
            }
        }
    }

    private var deleteDisabled: Bool {
        appState.isReadOnly || selectedGroupIDs.isEmpty
    }

    private var filteredGroups: [ResourceGroupSummary] {
        guard !searchText.isEmpty else { return groups }
        let query = searchText.lowercased()
        return groups.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var listHeader: some View {
        ListHeaderBar(
            title: "Resource Groups",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: deleteDisabled,
            deleteHelp: selectedGroupIDs.count <= 1 ? "Delete Resource Group" : "Delete \(selectedGroupIDs.count) Resource Groups",
            onRefresh: { loadGroups(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { groupsToDelete = groups.filter { selectedGroupIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var listContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: groups.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading resource groups...", onRetry: { loadGroups(force: true) }) {
            VStack(spacing: 0) {
                if groups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedGroupIDs) {
                    if groups.isEmpty {
                        EmptyStateView(icon: "square.3.layers.3d", message: "No resource groups")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredGroups) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if !group.description.isEmpty {
                            Text(group.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .selectionForeground()
                    .tag(group.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(group.name) }
                        if !group.groupArn.isEmpty {
                            Button("Copy ARN") { copyToClipboard(group.groupArn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Get Group") {
                                copyToClipboard(group.getGroupCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Groups") {
                                copyToClipboard(ResourceGroupSummary.listGroupsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Delete Group") {
                                copyToClipboard(group.deleteGroupCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Resource Group") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedGroupIDs.count > 1 && selectedGroupIDs.contains(group.id) {
                            let selected = groups.filter { selectedGroupIDs.contains($0.id) }
                            Button("Delete (\(selected.count) Groups)", role: .destructive) {
                                groupsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                groupsToDelete = [group]
                            }
                            .disabled(appState.isReadOnly)
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
                    Button("Create Resource Group") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: groups.count, selectedCount: selectedGroupIDs.count, noun: "group")
            }
        }
    }

    // MARK: - Data

    private func loadGroups(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listGroups() },
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

    private func deleteGroups(_ targets: [ResourceGroupSummary]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteGroup(name: $0.name)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedGroupIDs.subtract(deleted)
                if let active = activeGroup, deleted.contains(active.id) {
                    activeGroup = nil
                }
                loadGroups(force: true)
            }
        }
    }
}
