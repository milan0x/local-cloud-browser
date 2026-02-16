import SwiftUI
import AppKit

struct EventBridgeBusListView: View {
    @ObservedObject var service: EventBridgeService
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedBusIDs: Set<EventBridgeBus.ID>
    @Binding var activeBus: EventBridgeBus?
    var restoreBusName: String?

    @State private var buses: [EventBridgeBus] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var busesToDelete: [EventBridgeBus] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var busToShowDetail: EventBridgeBus?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            busListHeader
            Divider()
            busListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            EventBridgeCreateBusView(service: service, existingBusNames: Set(buses.map(\.name)))
                .onDisappear { loadBuses(force: true) }
        }
        .alert(
            busesToDelete.count == 1
                ? "Delete Event Bus"
                : "Delete \(busesToDelete.count) Event Buses",
            isPresented: Binding(
                get: { !busesToDelete.isEmpty },
                set: { if !$0 { busesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteBuses(busesToDelete)
            }
            Button("Cancel", role: .cancel) {
                busesToDelete = []
            }
        } message: {
            if busesToDelete.count == 1, let bus = busesToDelete.first {
                Text("Are you sure you want to delete \"\(bus.name)\"?\n\nAll rules and targets on this bus will be permanently deleted.")
            } else {
                let names = busesToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these event buses?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $busToShowDetail) { bus in
            EventBridgeBusDetailView(bus: bus)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadBuses() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && busesToDelete.isEmpty && busToShowDetail == nil && !isLoading }) {
            loadBuses(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedBusIDs = []
            activeBus = nil
            buses = []
            loadBuses(force: true)
        }
        .syncSelection(selectedBusIDs, items: buses, activeItem: $activeBus)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createRule:
                break // handled by rule browser
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeBus, !active.isDefault {
                    busesToDelete = [active]
                }
            case .viewDetails, .putEvent:
                break // handled by rule browser
            case .createSchedule, .deleteSelectedGroup:
                break // handled by scheduler views
            }
        }
    }

    private var busDeleteDisabled: Bool {
        appState.isReadOnly || selectedBusIDs.isEmpty
    }

    private var filteredBuses: [EventBridgeBus] {
        guard !searchText.isEmpty else { return buses }
        let query = searchText.lowercased()
        return buses.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Header

    private var busListHeader: some View {
        HStack {
            Text("Event Buses")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadBuses(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadBuses(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: busDeleteDisabled, help: selectedBusIDs.count <= 1 ? "Delete Event Bus" : "Delete \(selectedBusIDs.count) Event Buses") {
                let deletable = buses.filter { selectedBusIDs.contains($0.id) && !$0.isDefault }
                if !deletable.isEmpty {
                    busesToDelete = deletable
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var busListContent: some View {
        if isLoading && buses.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading event buses...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, buses.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadBuses(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if buses.isEmpty {
            EmptyStateView(icon: "bolt.horizontal", message: "No event buses")
            .contextMenu {
                Button("Create Event Bus") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if buses.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter event buses")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredBuses, selection: $selectedBusIDs) { bus in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bus.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if bus.isDefault {
                            StatusBadge(text: "default", color: .blue)
                        }
                    }
                    .tag(bus.id)
                    .contextMenu {
                        Button("View Details") {
                            busToShowDetail = bus
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(bus.name) }
                        if let arn = bus.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("List Rules") {
                                copyToClipboard(bus.listRulesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Event Bus") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedBusIDs.count > 1 && selectedBusIDs.contains(bus.id) {
                            let selected = buses.filter { selectedBusIDs.contains($0.id) && !$0.isDefault }
                            Button("Delete \(selected.count) Event Buses", role: .destructive) {
                                busesToDelete = selected
                            }
                            .disabled(appState.isReadOnly || selected.isEmpty)
                        } else {
                            Button("Delete", role: .destructive) {
                                busesToDelete = [bus]
                            }
                            .disabled(appState.isReadOnly || bus.isDefault)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Event Bus") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedBusIDs.count == 1,
                       let id = selectedBusIDs.first,
                       let bus = buses.first(where: { $0.id == id }) {
                        busToShowDetail = bus
                    }
                })

                // Status bar
                Divider()
                HStack {
                    Text("\(buses.count) bus\(buses.count == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedBusIDs.count > 1 {
                        Text("(\(selectedBusIDs.count) selected)")
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

    private func loadBuses(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listEventBuses()
                let freshBuses = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if buses != freshBuses {
                    buses = freshBuses
                }
                if !hasRestoredSession, let savedName = restoreBusName,
                   let bus = buses.first(where: { $0.name == savedName }) {
                    selectedBusIDs = [bus.id]
                    activeBus = bus
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

    private func deleteBuses(_ targets: [EventBridgeBus]) {
        Task {
            var deletedIDs: Set<EventBridgeBus.ID> = []
            for bus in targets {
                guard !bus.isDefault else { continue }
                do {
                    try await service.deleteEventBus(name: bus.name)
                    deletedIDs.insert(bus.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedBusIDs.subtract(deletedIDs)
                if let active = activeBus, deletedIDs.contains(active.id) {
                    activeBus = nil
                }
                loadBuses(force: true)
            }
        }
    }
}
