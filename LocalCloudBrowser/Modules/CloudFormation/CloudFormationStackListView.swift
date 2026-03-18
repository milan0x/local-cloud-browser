import SwiftUI
import AppKit

struct CloudFormationStackListView: View {
    @ObservedObject var service: CloudFormationService
    @ObservedObject var toolbarState: CloudFormationToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedStackIDs: Set<CloudFormationStack.ID>
    @Binding var activeStack: CloudFormationStack?
    var restoreStackName: String?

    @StateObject private var loader = PaginatedListLoader<CloudFormationStack>()
    private var stacks: [CloudFormationStack] { loader.items }
    @State private var pendingSelectName: String?
    @State private var showCreateSheet = false
    @State private var stacksToDelete: [CloudFormationStack] = []
    @State private var serviceError: ServiceError?
    @State private var stackToShowDetail: CloudFormationStack?
    @State private var searchText = ""
    @State private var deleteSuccessMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            stackListHeader
            Divider()
            stackListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            CloudFormationCreateStackView(service: service, existingStackNames: Set(stacks.map(\.stackName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadStacks(force: true) }
        }
        .deleteConfirmation(items: $stacksToDelete, noun: "Stack") { items in
            if items.count == 1, let stack = items.first {
                Text("Are you sure you want to delete \"\(stack.stackName)\"?\n\nAll resources in this stack will be deleted.")
            } else {
                let names = items.map(\.stackName).joined(separator: "\n")
                Text("Are you sure you want to delete these stacks?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteStacks($0) }
        .sheet(item: $stackToShowDetail) { stack in
            CloudFormationStackDetailView(service: service, stackName: stack.stackName)
        }
        .serviceErrorAlert(error: $serviceError)
        .alert("Stack Deleted", isPresented: Binding(get: { deleteSuccessMessage != nil }, set: { if !$0 { deleteSuccessMessage = nil } })) {
            Button("OK", role: .cancel) { deleteSuccessMessage = nil }
        } message: {
            if let msg = deleteSuccessMessage { Text(msg) }
        }
        .task { loadStacks() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && stacksToDelete.isEmpty && stackToShowDetail == nil && !loader.isLoading }) {
            loadStacks(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedStackIDs = []
            activeStack = nil
            loader.items = []
            loadStacks(force: true)
        }
        .syncSelection(selectedStackIDs, items: stacks, activeItem: $activeStack)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createStack:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeStack {
                    stacksToDelete = [active]
                }
            case .viewDetails, .viewTemplate:
                break // handled by browser
            }
        }
    }

    private var stackDeleteDisabled: Bool {
        appState.isReadOnly || selectedStackIDs.isEmpty
    }

    private var filteredStacks: [CloudFormationStack] {
        guard !searchText.isEmpty else { return stacks }
        let query = searchText.lowercased()
        return stacks.filter { $0.stackName.lowercased().contains(query) }
    }

    // MARK: - Header

    private var stackListHeader: some View {
        ListHeaderBar(
            title: "Stacks",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: stacks.count,
            deleteDisabled: stackDeleteDisabled,
            deleteHelp: selectedStackIDs.count <= 1 ? "Delete Stack" : "Delete \(selectedStackIDs.count) Stacks",
            onRefresh: { loadStacks(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: {
                let deletable = stacks.filter { selectedStackIDs.contains($0.id) }
                if !deletable.isEmpty { stacksToDelete = deletable }
            }
        )
    }

    // MARK: - Content

    private var stackListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: stacks.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading stacks...", emptyIcon: "square.stack.3d.down.right", emptyMessage: "No stacks", onRetry: { loadStacks(force: true) }) {
            VStack(spacing: 0) {
                if stacks.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter stacks")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedStackIDs) {
                    ForEach(filteredStacks) { stack in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stack.stackName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            StatusBadge(text: stack.stackStatus, color: stack.statusColor.swiftUIColor)
                            if let created = stack.creationTime {
                                Text(Self.dateFormatter.string(from: created))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .selectionForeground()
                    .tag(stack.id)
                    .contextMenu {
                        Button("View Details") {
                            stackToShowDetail = stack
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(stack.stackName) }
                        Button("Copy Stack ID") { copyToClipboard(stack.stackId) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Stack") {
                                copyToClipboard(stack.describeStackCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Resources") {
                                copyToClipboard(stack.listResourcesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Stack") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedStackIDs.count > 1 && selectedStackIDs.contains(stack.id) {
                            let selected = stacks.filter { selectedStackIDs.contains($0.id) }
                            Button("Delete \(selected.count) Stacks", role: .destructive) {
                                stacksToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                stacksToDelete = [stack]
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
                    Button("Create Stack") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedStackIDs.count == 1,
                       let id = selectedStackIDs.first,
                       let stack = stacks.first(where: { $0.id == id }) {
                        stackToShowDetail = stack
                    }
                })

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

                if filteredStacks.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.stackName.lowercased().contains(query) }
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

                ListStatusBar(totalCount: stacks.count, selectedCount: selectedStackIDs.count, noun: "stack", hasMorePages: loader.hasMorePages)
            }
        }
    }

    // MARK: - Data

    private func loadStacks(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listStacksPage(token: token) },
            sort: { $0.stackName.localizedStandardCompare($1.stackName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreStackName,
               let stack = items.first(where: { $0.stackName == savedName }) {
                selectedStackIDs = [stack.id]
                activeStack = stack
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let stack = items.first(where: { $0.stackName == name }) {
                selectedStackIDs = [stack.id]
                activeStack = stack
                pendingSelectName = nil
            }
        }
    }

    private func deleteStacks(_ targets: [CloudFormationStack]) {
        Task {
            selectedStackIDs.subtract(Set(targets.map(\.id)))
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteStack(name: $0.stackName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .cloudFormation, by: deleted.count)
                selectedStackIDs.subtract(deleted)
                if let active = activeStack, deleted.contains(active.id) { activeStack = nil }
                if error == nil {
                    deleteSuccessMessage = deleted.count == 1
                        ? "Stack deletion initiated."
                        : "\(deleted.count) stack deletions initiated."
                }
                loadStacks(force: true)
            }
        }
    }
}
