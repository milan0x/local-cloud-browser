import SwiftUI
import AppKit

struct Route53ZoneListView: View {
    @ObservedObject var service: Route53Service
    @ObservedObject var toolbarState: Route53ToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedZoneIDs: Set<Route53HostedZone.ID>
    @Binding var activeZone: Route53HostedZone?
    var restoreZoneId: String?

    @State private var pendingSelectName: String?
    @State private var showCreateSheet = false
    @State private var zonesToDelete: [Route53HostedZone] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<Route53HostedZone>()
    private var zones: [Route53HostedZone] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            zoneListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            Route53CreateZoneView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadZones(force: true) }
        }
        .deleteConfirmation(items: $zonesToDelete, noun: "Hosted Zone") { items in
            if items.count == 1, let zone = items.first {
                Text("Are you sure you want to delete hosted zone \"\(zone.displayName)\"?\n\nAll record sets in this zone will be deleted.")
            } else {
                Text("Are you sure you want to delete \(items.count) hosted zones?\n\nAll record sets in these zones will be deleted.")
            }
        } onDelete: { deleteZones($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadZones() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && zonesToDelete.isEmpty && !loader.isLoading }) {
            loadZones(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedZoneIDs = []
            activeZone = nil
            loader.items = []
            loadZones(force: true)
        }
        .syncSelection(selectedZoneIDs, items: zones, activeItem: $activeZone)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createZone:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteZone:
                toolbarState.pendingAction = nil
                if let active = activeZone {
                    zonesToDelete = [active]
                }
            case .createRecord:
                break // handled by record set browser
            case .createEndpoint, .createRule, .deleteEndpoint:
                break // handled by resolver list
            }
        }
    }

    private var filteredZones: [Route53HostedZone] {
        guard !searchText.isEmpty else { return zones }
        let query = searchText.lowercased()
        return zones.filter {
            $0.name.lowercased().contains(query) ||
            $0.comment.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var zoneListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: zones.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading zones...", onRetry: { loadZones(force: true) }) {
            if zones.isEmpty {
                EmptyStateView(icon: "globe.americas", message: "No hosted zones")
                .contextMenu {
                    Button("Create Hosted Zone") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                VStack(spacing: 0) {
                    if zones.count > 5 {
                        SearchBarView(query: $searchText, placeholder: "Filter zones")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Divider()
                    }
                    List(filteredZones, selection: $selectedZoneIDs) { zone in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(zone.displayName)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                if !zone.comment.isEmpty {
                                    Text(zone.comment)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(zone.recordSetCount)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            privateBadge(zone.privateZone)
                        }
                        .selectionForeground()
                        .tag(zone.id)
                        .contextMenu {
                            Button("Copy Name") { copyToClipboard(zone.name) }
                            Button("Copy Zone ID") { copyToClipboard(zone.id) }
                            Menu("Copy as AWS CLI") {
                                Button("List Record Sets") {
                                    copyToClipboard(zone.listRecordSetsCLI(endpointUrl: appState.endpoint, region: appState.region))
                                }
                                Button("List Hosted Zones") {
                                    copyToClipboard(Route53HostedZone.listZonesCLI(endpointUrl: appState.endpoint, region: appState.region))
                                }
                                Button("Delete Hosted Zone") {
                                    copyToClipboard(zone.deleteZoneCLI(endpointUrl: appState.endpoint, region: appState.region))
                                }
                            }
                            Divider()
                            Button("Create Hosted Zone") {
                                showCreateSheet = true
                            }
                            .disabled(appState.isReadOnly)
                            Divider()
                            if selectedZoneIDs.count > 1 && selectedZoneIDs.contains(zone.id) {
                                let selected = zones.filter { selectedZoneIDs.contains($0.id) }
                                Button("Delete (\(selected.count) Zones)", role: .destructive) {
                                    zonesToDelete = selected
                                }
                                .disabled(appState.isReadOnly)
                            } else {
                                Button("Delete", role: .destructive) {
                                    zonesToDelete = [zone]
                                }
                                .disabled(appState.isReadOnly)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if loader.errorMessage != nil {
                            ConnectionLostBanner()
                        }
                    }
                    .contextMenu {
                        Button("Create Hosted Zone") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                    }

                    ListStatusBar(totalCount: zones.count, selectedCount: selectedZoneIDs.count, noun: "zone")
                }
            }
        }
    }

    private func privateBadge(_ isPrivate: Bool) -> some View {
        StatusBadge(text: isPrivate ? "Private" : "Public", color: isPrivate ? .orange : .green)
    }

    // MARK: - Data

    private func loadZones(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listHostedZones() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedId = restoreZoneId,
               let zone = items.first(where: { $0.id == savedId }) {
                selectedZoneIDs = [zone.id]
                activeZone = zone
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let zone = items.first(where: { $0.name == name }) {
                selectedZoneIDs = [zone.id]
                activeZone = zone
                pendingSelectName = nil
            }
        }
    }

    private func deleteZones(_ targets: [Route53HostedZone]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteHostedZone(id: $0.id)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedZoneIDs.subtract(deleted)
                if let active = activeZone, deleted.contains(active.id) { activeZone = nil }
                loadZones(force: true)
            }
        }
    }
}
