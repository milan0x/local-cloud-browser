import SwiftUI
import AppKit

struct Route53ZoneListView: View {
    @ObservedObject var service: Route53Service
    @ObservedObject var toolbarState: Route53ToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedZoneIDs: Set<Route53HostedZone.ID>
    @Binding var activeZone: Route53HostedZone?
    var restoreZoneId: String?

    @State private var zones: [Route53HostedZone] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var zonesToDelete: [Route53HostedZone] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            zoneListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            Route53CreateZoneView(service: service)
                .onDisappear { loadZones(force: true) }
        }
        .alert(
            zonesToDelete.count == 1
                ? "Delete Hosted Zone"
                : "Delete \(zonesToDelete.count) Hosted Zones",
            isPresented: Binding(
                get: { !zonesToDelete.isEmpty },
                set: { if !$0 { zonesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteZones(zonesToDelete)
            }
            Button("Cancel", role: .cancel) {
                zonesToDelete = []
            }
        } message: {
            if zonesToDelete.count == 1, let zone = zonesToDelete.first {
                Text("Are you sure you want to delete hosted zone \"\(zone.displayName)\"?\n\nAll record sets in this zone will be deleted.")
            } else {
                Text("Are you sure you want to delete \(zonesToDelete.count) hosted zones?\n\nAll record sets in these zones will be deleted.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadZones() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && zonesToDelete.isEmpty && !isLoading }) {
            loadZones(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedZoneIDs = []
            activeZone = nil
            zones = []
            loadZones(force: true)
        }
        .onChange(of: selectedZoneIDs) {
            if selectedZoneIDs.count == 1, let id = selectedZoneIDs.first {
                activeZone = zones.first { $0.id == id }
            } else {
                activeZone = nil
            }
        }
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

    @ViewBuilder
    private var zoneListContent: some View {
        if isLoading && zones.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading zones...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, zones.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadZones(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if zones.isEmpty {
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
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Hosted Zone") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(zones.count) zone\(zones.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedZoneIDs.count > 1 {
                        Text("(\(selectedZoneIDs.count) selected)")
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

    private func privateBadge(_ isPrivate: Bool) -> some View {
        StatusBadge(text: isPrivate ? "Private" : "Public", color: isPrivate ? .orange : .green)
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

    private func loadZones(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listHostedZones()
                let freshZones = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if zones != freshZones {
                    zones = freshZones
                }
                if !hasRestoredSession, let savedId = restoreZoneId,
                   let zone = zones.first(where: { $0.id == savedId }) {
                    selectedZoneIDs = [zone.id]
                    activeZone = zone
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

    private func deleteZones(_ targets: [Route53HostedZone]) {
        Task {
            var deletedIDs: Set<Route53HostedZone.ID> = []
            for zone in targets {
                do {
                    try await service.deleteHostedZone(id: zone.id)
                    deletedIDs.insert(zone.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedZoneIDs.subtract(deletedIDs)
                if let active = activeZone, deletedIDs.contains(active.id) {
                    activeZone = nil
                }
                loadZones(force: true)
            }
        }
    }
}
