import SwiftUI
import AppKit

struct StepFunctionsStateMachineListView: View {
    @ObservedObject var service: StepFunctionsService
    @ObservedObject var toolbarState: StepFunctionsToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedIDs: Set<StateMachineSummary.ID>
    @Binding var activeMachine: StateMachineSummary?
    var restoreName: String?

    @StateObject private var loader = PaginatedListLoader<StateMachineSummary>()
    private var machines: [StateMachineSummary] { loader.items }
    @State private var pendingSelectName: String?
    @State private var showCreateSheet = false
    @State private var machinesToDelete: [StateMachineSummary] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            listContent
        }
        .sheet(isPresented: $showCreateSheet) {
            StepFunctionsCreateStateMachineView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadMachines(force: true) }
        }
        .deleteConfirmation(items: $machinesToDelete, noun: "State Machine") { items in
            if items.count == 1, let machine = items.first {
                Text("Are you sure you want to delete state machine \"\(machine.name)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) state machines?")
            }
        } onDelete: { deleteMachines($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadMachines() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && machinesToDelete.isEmpty && !loader.isLoading }) {
            loadMachines(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedIDs = []
            activeMachine = nil
            loader.items = []
            loadMachines(force: true)
        }
        .syncSelection(selectedIDs, items: machines, activeItem: $activeMachine)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createStateMachine:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteStateMachine:
                toolbarState.pendingAction = nil
                if let active = activeMachine {
                    machinesToDelete = [active]
                }
            case .startExecution:
                break // handled by module view
            }
        }
    }

    private var deleteDisabled: Bool {
        appState.isReadOnly || selectedIDs.isEmpty
    }

    private var filteredMachines: [StateMachineSummary] {
        guard !searchText.isEmpty else { return machines }
        let query = searchText.lowercased()
        return machines.filter {
            $0.name.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var listHeader: some View {
        ListHeaderBar(
            title: "State Machines",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: machines.count,
            deleteDisabled: deleteDisabled,
            deleteHelp: selectedIDs.count <= 1 ? "Delete State Machine" : "Delete \(selectedIDs.count) State Machines",
            onRefresh: { loadMachines(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { machinesToDelete = machines.filter { selectedIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var listContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: machines.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading state machines...", emptyIcon: "arrow.triangle.branch", emptyMessage: "No state machines", onRetry: { loadMachines(force: true) }) {
            VStack(spacing: 0) {
                if machines.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter state machines")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedIDs) {
                    ForEach(filteredMachines) { machine in
                    HStack {
                        Text(machine.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        typeBadge(machine.type)
                    }
                    .selectionForeground()
                    .tag(machine.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(machine.name) }
                        Button("Copy ARN") { copyToClipboard(machine.stateMachineArn) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe State Machine") {
                                copyToClipboard(machine.describeStateMachineCLI(
                                    endpointUrl: appState.endpoint, region: appState.region
                                ))
                            }
                            Button("List State Machines") {
                                copyToClipboard(StateMachineSummary.listStateMachinesCLI(
                                    endpointUrl: appState.endpoint, region: appState.region
                                ))
                            }
                        }
                        Divider()
                        Button("Create State Machine") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedIDs.count > 1 && selectedIDs.contains(machine.id) {
                            let selected = machines.filter { selectedIDs.contains($0.id) }
                            Button("Delete \(selected.count) State Machines", role: .destructive) {
                                machinesToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                machinesToDelete = [machine]
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
                    Button("Create State Machine") {
                        showCreateSheet = true
                    }
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

                if filteredMachines.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.name.lowercased().contains(query) }
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

                ListStatusBar(totalCount: machines.count, selectedCount: selectedIDs.count, noun: "state machine", hasMorePages: loader.hasMorePages)
            }
        }
    }

    private func typeBadge(_ type: String) -> some View {
        StatusBadge(text: type, color: typeColor(type))
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "STANDARD": .blue
        case "EXPRESS": .purple
        default: .gray
        }
    }

    // MARK: - Data

    private func loadMachines(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listStateMachinesPage(token: token) },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreName,
               let machine = items.first(where: { $0.name == savedName }) {
                selectedIDs = [machine.id]
                activeMachine = machine
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let machine = items.first(where: { $0.name == name }) {
                selectedIDs = [machine.id]
                activeMachine = machine
                pendingSelectName = nil
            }
        }
    }

    private func deleteMachines(_ targets: [StateMachineSummary]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteStateMachine(arn: $0.stateMachineArn)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .stepFunctions, by: deleted.count)
                selectedIDs.subtract(deleted)
                if let active = activeMachine, deleted.contains(active.id) {
                    activeMachine = nil
                }
                loadMachines(force: true)
            }
        }
    }

}
