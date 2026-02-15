import SwiftUI
import AppKit

struct ResourceGroupsListView: View {
    @ObservedObject var service: ResourceGroupsService
    @ObservedObject var toolbarState: ResourceGroupsToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedGroupIDs: Set<ResourceGroupSummary.ID>
    @Binding var activeGroup: ResourceGroupSummary?
    var restoreGroupName: String?

    @State private var groups: [ResourceGroupSummary] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var groupsToDelete: [ResourceGroupSummary] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            listContent
        }
        .sheet(isPresented: $showCreateSheet) {
            ResourceGroupsCreateView(service: service)
                .onDisappear { loadGroups(force: true) }
        }
        .alert(
            groupsToDelete.count == 1
                ? "Delete Resource Group"
                : "Delete \(groupsToDelete.count) Resource Groups",
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
                Text("Are you sure you want to delete the resource group \"\(group.name)\"?")
            } else {
                Text("Are you sure you want to delete \(groupsToDelete.count) resource groups?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadGroups() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && groupsToDelete.isEmpty && !isLoading else { return }
            loadGroups(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedGroupIDs = []
            activeGroup = nil
            groups = []
            loadGroups(force: true)
        }
        .onChange(of: appState.region) {
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
        HStack {
            Text("Resource Groups")
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

            ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled, help: selectedGroupIDs.count <= 1 ? "Delete Resource Group" : "Delete \(selectedGroupIDs.count) Resource Groups") {
                groupsToDelete = groups.filter { selectedGroupIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var listContent: some View {
        if isLoading && groups.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading resource groups...")
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
            EmptyStateView(icon: "square.3.layers.3d", message: "No resource groups")
            .contextMenu {
                Button("Create Resource Group") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if groups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredGroups, selection: $selectedGroupIDs) { group in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Resource Group") {
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
                let loaded = try await service.listGroups()
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

    private func deleteGroups(_ targets: [ResourceGroupSummary]) {
        Task {
            var deletedIDs: Set<ResourceGroupSummary.ID> = []
            for group in targets {
                do {
                    try await service.deleteGroup(name: group.name)
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
