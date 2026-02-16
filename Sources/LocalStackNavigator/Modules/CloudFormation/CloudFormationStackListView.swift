import SwiftUI
import AppKit

struct CloudFormationStackListView: View {
    @ObservedObject var service: CloudFormationService
    @ObservedObject var toolbarState: CloudFormationToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedStackIDs: Set<CloudFormationStack.ID>
    @Binding var activeStack: CloudFormationStack?
    var restoreStackName: String?

    @State private var stacks: [CloudFormationStack] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var stacksToDelete: [CloudFormationStack] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var stackToShowDetail: CloudFormationStack?
    @State private var searchText = ""

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
            CloudFormationCreateStackView(service: service, existingStackNames: Set(stacks.map(\.stackName)))
                .onDisappear { loadStacks(force: true) }
        }
        .alert(
            stacksToDelete.count == 1
                ? "Delete Stack"
                : "Delete \(stacksToDelete.count) Stacks",
            isPresented: Binding(
                get: { !stacksToDelete.isEmpty },
                set: { if !$0 { stacksToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteStacks(stacksToDelete)
            }
            Button("Cancel", role: .cancel) {
                stacksToDelete = []
            }
        } message: {
            if stacksToDelete.count == 1, let stack = stacksToDelete.first {
                Text("Are you sure you want to delete \"\(stack.stackName)\"?\n\nAll resources in this stack will be deleted.")
            } else {
                let names = stacksToDelete.map(\.stackName).joined(separator: "\n")
                Text("Are you sure you want to delete these stacks?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $stackToShowDetail) { stack in
            CloudFormationStackDetailView(service: service, stackName: stack.stackName)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadStacks() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && stacksToDelete.isEmpty && stackToShowDetail == nil && !isLoading }) {
            loadStacks(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedStackIDs = []
            activeStack = nil
            stacks = []
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
        HStack {
            Text("Stacks")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadStacks(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadStacks(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: stackDeleteDisabled, help: selectedStackIDs.count <= 1 ? "Delete Stack" : "Delete \(selectedStackIDs.count) Stacks") {
                let deletable = stacks.filter { selectedStackIDs.contains($0.id) }
                if !deletable.isEmpty {
                    stacksToDelete = deletable
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var stackListContent: some View {
        if isLoading && stacks.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading stacks...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, stacks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadStacks(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stacks.isEmpty {
            EmptyStateView(icon: "square.stack.3d.down.right", message: "No stacks")
            .contextMenu {
                Button("Create Stack") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if stacks.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter stacks")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredStacks, selection: $selectedStackIDs) { stack in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
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

                // Status bar
                Divider()
                HStack {
                    Text("\(stacks.count) stack\(stacks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedStackIDs.count > 1 {
                        Text("(\(selectedStackIDs.count) selected)")
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

    // MARK: - Data

    private func loadStacks(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listStacks()
                let freshStacks = loaded.sorted { $0.stackName.localizedStandardCompare($1.stackName) == .orderedAscending }
                if stacks != freshStacks {
                    stacks = freshStacks
                }
                if !hasRestoredSession, let savedName = restoreStackName,
                   let stack = stacks.first(where: { $0.stackName == savedName }) {
                    selectedStackIDs = [stack.id]
                    activeStack = stack
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

    private func deleteStacks(_ targets: [CloudFormationStack]) {
        Task {
            var deletedIDs: Set<CloudFormationStack.ID> = []
            for stack in targets {
                do {
                    try await service.deleteStack(name: stack.stackName)
                    deletedIDs.insert(stack.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedStackIDs.subtract(deletedIDs)
                if let active = activeStack, deletedIDs.contains(active.id) {
                    activeStack = nil
                }
                loadStacks(force: true)
            }
        }
    }
}
