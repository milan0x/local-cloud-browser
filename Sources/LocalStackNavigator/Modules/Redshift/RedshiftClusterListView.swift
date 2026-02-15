import SwiftUI
import AppKit

struct RedshiftClusterListView: View {
    @ObservedObject var service: RedshiftService
    @ObservedObject var toolbarState: RedshiftToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedClusterIDs: Set<RedshiftCluster.ID>
    @Binding var activeCluster: RedshiftCluster?
    var restoreClusterId: String?

    @State private var clusters: [RedshiftCluster] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var clustersToDelete: [RedshiftCluster] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            clusterListHeader
            Divider()
            clusterListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            RedshiftCreateClusterView(service: service)
                .onDisappear { loadClusters(force: true) }
        }
        .alert(
            clustersToDelete.count == 1
                ? "Delete Cluster"
                : "Delete \(clustersToDelete.count) Clusters",
            isPresented: Binding(
                get: { !clustersToDelete.isEmpty },
                set: { if !$0 { clustersToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteClusters(clustersToDelete)
            }
            Button("Cancel", role: .cancel) {
                clustersToDelete = []
            }
        } message: {
            if clustersToDelete.count == 1, let cluster = clustersToDelete.first {
                Text("Are you sure you want to delete cluster \"\(cluster.clusterIdentifier)\"?\n\nThe final snapshot will be skipped.")
            } else {
                Text("Are you sure you want to delete \(clustersToDelete.count) clusters?\n\nFinal snapshots will be skipped.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadClusters() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && clustersToDelete.isEmpty && !isLoading else { return }
            loadClusters(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedClusterIDs = []
            activeCluster = nil
            clusters = []
            loadClusters(force: true)
        }
        .onChange(of: appState.region) {
            selectedClusterIDs = []
            activeCluster = nil
            clusters = []
            loadClusters(force: true)
        }
        .onChange(of: selectedClusterIDs) {
            if selectedClusterIDs.count == 1, let id = selectedClusterIDs.first {
                activeCluster = clusters.first { $0.id == id }
            } else {
                activeCluster = nil
            }
        }
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
        HStack {
            Text("Clusters")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadClusters(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadClusters(force: true)
            }

            Button {
                clustersToDelete = clusters.filter { selectedClusterIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(clusterDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(clusterDeleteDisabled)
            .help(selectedClusterIDs.count <= 1 ? "Delete Cluster" : "Delete \(selectedClusterIDs.count) Clusters")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var clusterListContent: some View {
        if isLoading && clusters.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading clusters...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, clusters.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadClusters(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if clusters.isEmpty {
            EmptyStateView(icon: "cylinder.split.1x2", message: "No clusters")
            .contextMenu {
                Button("Create Cluster") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if clusters.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter clusters")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredClusters, selection: $selectedClusterIDs) { cluster in
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
                            Button("Delete (\(selected.count) Clusters)", role: .destructive) {
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Cluster") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(clusters.count) cluster\(clusters.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedClusterIDs.count > 1 {
                        Text("(\(selectedClusterIDs.count) selected)")
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

    private func statusBadge(for cluster: RedshiftCluster) -> some View {
        Text(cluster.clusterStatus)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(statusColor(cluster.clusterStatus).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(cluster.clusterStatus))
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

    private func loadClusters(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.describeClusters()
                let freshClusters = loaded.sorted { $0.clusterIdentifier.localizedStandardCompare($1.clusterIdentifier) == .orderedAscending }
                if clusters != freshClusters {
                    clusters = freshClusters
                }
                if !hasRestoredSession, let savedId = restoreClusterId,
                   let cluster = clusters.first(where: { $0.clusterIdentifier == savedId }) {
                    selectedClusterIDs = [cluster.id]
                    activeCluster = cluster
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

    private func deleteClusters(_ targets: [RedshiftCluster]) {
        Task {
            var deletedIDs: Set<RedshiftCluster.ID> = []
            for cluster in targets {
                do {
                    try await service.deleteCluster(id: cluster.clusterIdentifier)
                    deletedIDs.insert(cluster.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedClusterIDs.subtract(deletedIDs)
                if let active = activeCluster, deletedIDs.contains(active.id) {
                    activeCluster = nil
                }
                loadClusters(force: true)
            }
        }
    }
}
