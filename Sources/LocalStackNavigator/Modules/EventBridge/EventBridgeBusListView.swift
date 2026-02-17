import SwiftUI
import AppKit

struct EventBridgeBusListView: View {
    @ObservedObject var service: EventBridgeService
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedBusIDs: Set<EventBridgeBus.ID>
    @Binding var activeBus: EventBridgeBus?
    var restoreBusName: String?

    @State private var showCreateSheet = false
    @State private var busesToDelete: [EventBridgeBus] = []
    @State private var serviceError: ServiceError?
    @State private var busToShowDetail: EventBridgeBus?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<EventBridgeBus>()
    private var buses: [EventBridgeBus] { loader.items }

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
        .deleteConfirmation(items: $busesToDelete, noun: "Event Bus", pluralNoun: "Event Buses") { items in
            if items.count == 1, let bus = items.first {
                Text("Are you sure you want to delete \"\(bus.name)\"?\n\nAll rules and targets on this bus will be permanently deleted.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these event buses?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteBuses($0) }
        .sheet(item: $busToShowDetail) { bus in
            EventBridgeBusDetailView(bus: bus)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadBuses() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && busesToDelete.isEmpty && busToShowDetail == nil && !loader.isLoading }) {
            loadBuses(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedBusIDs = []
            activeBus = nil
            loader.items = []
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
        ListHeaderBar(
            title: "Event Buses",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: busDeleteDisabled,
            deleteHelp: selectedBusIDs.count <= 1 ? "Delete Event Bus" : "Delete \(selectedBusIDs.count) Event Buses",
            onRefresh: { loadBuses(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: {
                let deletable = buses.filter { selectedBusIDs.contains($0.id) && !$0.isDefault }
                if !deletable.isEmpty { busesToDelete = deletable }
            }
        )
    }

    // MARK: - Content

    private var busListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: buses.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading event buses...", onRetry: { loadBuses(force: true) }) {
            VStack(spacing: 0) {
                if buses.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter event buses")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedBusIDs) {
                    if buses.isEmpty {
                        EmptyStateView(icon: "bolt.horizontal", message: "No event buses")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredBuses) { bus in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bus.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if bus.isDefault {
                            StatusBadge(text: "default", color: .blue)
                        }
                    }
                    .foregroundStyle(selectedBusIDs.contains(bus.id) ? Color.white : Color.primary)
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
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
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

                ListStatusBar(totalCount: buses.count, selectedCount: selectedBusIDs.count, noun: "event bus")
            }
        }
    }

    // MARK: - Data

    private func loadBuses(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listEventBuses() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreBusName,
               let bus = items.first(where: { $0.name == savedName }) {
                selectedBusIDs = [bus.id]
                activeBus = bus
            }
            loader.hasRestoredSession = true
        }
    }

    private func deleteBuses(_ targets: [EventBridgeBus]) {
        let nonDefault = targets.filter { !$0.isDefault }
        Task {
            let (deletedIDs, lastError) = await batchDelete(nonDefault) { bus in
                try await service.deleteEventBus(name: bus.name)
            }
            if let lastError { serviceError = lastError }
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
