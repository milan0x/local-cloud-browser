import SwiftUI
import AppKit

struct StepFunctionsStateMachineListView: View {
    @ObservedObject var service: StepFunctionsService
    @ObservedObject var toolbarState: StepFunctionsToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedIDs: Set<StateMachineSummary.ID>
    @Binding var activeMachine: StateMachineSummary?
    var restoreName: String?

    @State private var machines: [StateMachineSummary] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var machinesToDelete: [StateMachineSummary] = []
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
            StepFunctionsCreateStateMachineView(service: service)
                .onDisappear { loadMachines(force: true) }
        }
        .alert(
            machinesToDelete.count == 1
                ? "Delete State Machine"
                : "Delete \(machinesToDelete.count) State Machines",
            isPresented: Binding(
                get: { !machinesToDelete.isEmpty },
                set: { if !$0 { machinesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteMachines(machinesToDelete)
            }
            Button("Cancel", role: .cancel) {
                machinesToDelete = []
            }
        } message: {
            if machinesToDelete.count == 1, let machine = machinesToDelete.first {
                Text("Are you sure you want to delete state machine \"\(machine.name)\"?")
            } else {
                Text("Are you sure you want to delete \(machinesToDelete.count) state machines?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadMachines() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && machinesToDelete.isEmpty && !isLoading }) {
            loadMachines(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedIDs = []
            activeMachine = nil
            machines = []
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
        HStack {
            Text("State Machines")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadMachines(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadMachines(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled, help: selectedIDs.count <= 1 ? "Delete State Machine" : "Delete \(selectedIDs.count) State Machines") {
                machinesToDelete = machines.filter { selectedIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var listContent: some View {
        if isLoading && machines.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading state machines...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, machines.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadMachines(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if machines.isEmpty {
            EmptyStateView(icon: "arrow.triangle.branch", message: "No state machines")
            .contextMenu {
                Button("Create State Machine") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if machines.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter state machines")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredMachines, selection: $selectedIDs) { machine in
                    HStack {
                        Text(machine.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        typeBadge(machine.type)
                    }
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
                            Button("Delete (\(selected.count) State Machines)", role: .destructive) {
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create State Machine") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(machines.count) state machine\(machines.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedIDs.count > 1 {
                        Text("(\(selectedIDs.count) selected)")
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
                let loaded = try await service.listStateMachines()
                let sorted = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if machines != sorted {
                    machines = sorted
                }
                if !hasRestoredSession, let savedName = restoreName,
                   let machine = machines.first(where: { $0.name == savedName }) {
                    selectedIDs = [machine.id]
                    activeMachine = machine
                }
                hasRestoredSession = true
                if !silent { errorMessage = nil }
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

    private func deleteMachines(_ targets: [StateMachineSummary]) {
        Task {
            var deletedIDs: Set<StateMachineSummary.ID> = []
            for machine in targets {
                do {
                    try await service.deleteStateMachine(arn: machine.stateMachineArn)
                    deletedIDs.insert(machine.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedIDs.subtract(deletedIDs)
                if let active = activeMachine, deletedIDs.contains(active.id) {
                    activeMachine = nil
                }
                loadMachines(force: true)
            }
        }
    }
}
