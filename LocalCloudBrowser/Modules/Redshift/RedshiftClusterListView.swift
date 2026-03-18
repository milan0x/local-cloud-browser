import SwiftUI
import AppKit

struct RedshiftClusterListView: View {
    @ObservedObject var service: RedshiftService
    @ObservedObject var toolbarState: RedshiftToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedClusterIDs: Set<RedshiftCluster.ID>
    @Binding var activeCluster: RedshiftCluster?
    var restoreClusterId: String?

    @State private var showCreateSheet = false
    @State private var clustersToDelete: [RedshiftCluster] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = ListLoader<RedshiftCluster>()
    private var clusters: [RedshiftCluster] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            clusterListHeader
            Divider()
            clusterListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            RedshiftCreateClusterView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadClusters(force: true) }
        }
        .deleteConfirmation(items: $clustersToDelete, noun: "Cluster") { items in
            if items.count == 1, let cluster = items.first {
                Text("Are you sure you want to delete cluster \"\(cluster.clusterIdentifier)\"?\n\nThe final snapshot will be skipped.")
            } else {
                Text("Are you sure you want to delete \(items.count) clusters?\n\nFinal snapshots will be skipped.")
            }
        } onDelete: { deleteClusters($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadClusters() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && clustersToDelete.isEmpty && !loader.isLoading }) {
            loadClusters(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedClusterIDs = []
            activeCluster = nil
            loader.items = []
            loadClusters(force: true)
        }
        .syncSelection(selectedClusterIDs, items: clusters, activeItem: $activeCluster)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createCluster:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteCluster:
                toolbarState.pendingAction = nil
                if let active = activeCluster {
                    clustersToDelete = [active]
                }
            }
        }
    }

    private var clusterDeleteDisabled: Bool {
        appState.isReadOnly || selectedClusterIDs.isEmpty
    }

    private var filteredClusters: [RedshiftCluster] {
        guard !searchText.isEmpty else { return clusters }
        let query = searchText.lowercased()
        return clusters.filter {
            $0.clusterIdentifier.lowercased().contains(query) ||
            $0.nodeType.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var clusterListHeader: some View {
        ListHeaderBar(
            title: "Clusters",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: clusters.count,
            deleteDisabled: clusterDeleteDisabled,
            deleteHelp: selectedClusterIDs.count <= 1 ? "Delete Cluster" : "Delete \(selectedClusterIDs.count) Clusters",
            onRefresh: { loadClusters(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { clustersToDelete = clusters.filter { selectedClusterIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var clusterListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: clusters.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading clusters...", emptyIcon: "cylinder.split.1x2", emptyMessage: "No clusters", onRetry: { loadClusters(force: true) }) {
            VStack(spacing: 0) {
                if clusters.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter clusters")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedClusterIDs) {
                    ForEach(filteredClusters) { cluster in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cluster.clusterIdentifier)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(cluster.nodeType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        statusBadge(for: cluster)
                    }
                    .selectionForeground()
                    .tag(cluster.id)
                    .contextMenu {
                        Button("Copy Identifier") { copyToClipboard(cluster.clusterIdentifier) }
                        if !cluster.endpointString.isEmpty {
                            Button("Copy Endpoint") { copyToClipboard(cluster.endpointString) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Clusters") {
                                copyToClipboard(cluster.describeClustersCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Clusters") {
                                copyToClipboard(RedshiftCluster.listClustersCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Cluster") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedClusterIDs.count > 1 && selectedClusterIDs.contains(cluster.id) {
                            let selected = clusters.filter { selectedClusterIDs.contains($0.id) }
                            Button("Delete \(selected.count) Clusters", role: .destructive) {
                                clustersToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                clustersToDelete = [cluster]
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
                    Button("Create Cluster") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: clusters.count, selectedCount: selectedClusterIDs.count, noun: "cluster")
            }
        }
    }

    private func statusBadge(for cluster: RedshiftCluster) -> some View {
        StatusBadge(text: cluster.clusterStatus, color: statusColor(cluster.clusterStatus))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "available": .green
        case "creating", "modifying": .blue
        case "deleting": .red
        case "paused": .orange
        default: .gray
        }
    }

    // MARK: - Data

    private func loadClusters(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.describeClusters() },
            sort: { $0.clusterIdentifier.localizedStandardCompare($1.clusterIdentifier) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedId = restoreClusterId,
               let cluster = items.first(where: { $0.clusterIdentifier == savedId }) {
                selectedClusterIDs = [cluster.id]
                activeCluster = cluster
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let cluster = items.first(where: { $0.clusterIdentifier == name }) {
                selectedClusterIDs = [cluster.id]
                activeCluster = cluster
                pendingSelectName = nil
            }
        }
    }

    private func deleteClusters(_ targets: [RedshiftCluster]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteCluster(id: $0.clusterIdentifier)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .redshift, by: deleted.count)
                selectedClusterIDs.subtract(deleted)
                if let active = activeCluster, deleted.contains(active.id) { activeCluster = nil }
                loadClusters(force: true)
            }
        }
    }

}
