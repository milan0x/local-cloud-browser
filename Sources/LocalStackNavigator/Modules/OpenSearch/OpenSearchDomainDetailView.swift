import SwiftUI
import AppKit

struct OpenSearchDomainDetailView: View {
    @ObservedObject var service: OpenSearchService
    let domain: OpenSearchDomain
    @ObservedObject var toolbarState: OpenSearchToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var serviceError: ServiceError?
    @State private var domainsToDelete: [OpenSearchDomain] = []
    @State private var clusterHealth: ClusterHealth?
    @State private var indices: [OpenSearchIndex] = []
    @State private var isLoadingCluster = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                domainInfoSection
                clusterConfigSection
                storageSection
                clusterHealthSection
                indicesSection
            }
            .padding(16)
        }
        .task(id: domain.id) {
            await loadClusterData()
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .deleteDomain:
                toolbarState.pendingAction = nil
                domainsToDelete = [domain]
            case .createDomain:
                break // handled by list view
            }
        }
        .alert(
            "Delete Domain",
            isPresented: Binding(
                get: { !domainsToDelete.isEmpty },
                set: { if !$0 { domainsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let target = domainsToDelete.first {
                    deleteDomain(target)
                }
            }
            Button("Cancel", role: .cancel) {
                domainsToDelete = []
            }
        } message: {
            if let target = domainsToDelete.first {
                Text("Are you sure you want to delete domain \"\(target.domainName)\"?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Text(domain.domainName)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)
            statusBadge
            engineBadge
            Spacer()
            if !domain.endpoint.isEmpty {
                Button {
                    if let url = URL(string: domain.endpoint) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open cluster endpoint in browser")
            }
        }
    }

    private var statusBadge: some View {
        Text(domain.status)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch domain.status {
        case "Active": .green
        case "Processing": .blue
        case "Deleting": .red
        default: .gray
        }
    }

    private var engineBadge: some View {
        Text(domain.engineDisplayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.1), in: Capsule())
            .foregroundStyle(.orange)
    }

    // MARK: - Domain Info

    private var domainInfoSection: some View {
        GroupBox("Domain Info") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Name") {
                    CopyableValue(text: domain.domainName, monospaced: true)
                }
                if !domain.domainId.isEmpty {
                    labeledRow("Domain ID") {
                        CopyableValue(text: domain.domainId, monospaced: true)
                    }
                }
                if !domain.arn.isEmpty {
                    labeledRow("ARN") {
                        CopyableValue(text: domain.arn, monospaced: true)
                    }
                }
                if !domain.endpoint.isEmpty {
                    labeledRow("Endpoint") {
                        CopyableValue(text: domain.endpoint, monospaced: true)
                    }
                } else {
                    labeledRow("Endpoint") {
                        Text("Not available")
                            .foregroundStyle(.secondary)
                    }
                }
                labeledRow("Engine") {
                    Text(domain.engineDisplayName)
                }
                labeledRow("Status") {
                    Text(domain.status)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Cluster Configuration

    private var clusterConfigSection: some View {
        GroupBox("Cluster Configuration") {
            VStack(alignment: .leading, spacing: 8) {
                if !domain.instanceType.isEmpty {
                    labeledRow("Instance Type") {
                        Text(domain.instanceType)
                            .font(.body.monospaced())
                    }
                }
                labeledRow("Instance Count") {
                    Text(String(domain.instanceCount))
                }
            }
            .padding(4)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        GroupBox("Storage") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("EBS Enabled") {
                    boolBadge(domain.ebsEnabled)
                }
                if domain.ebsEnabled {
                    if !domain.volumeType.isEmpty {
                        labeledRow("Volume Type") {
                            Text(domain.volumeType)
                                .font(.body.monospaced())
                        }
                    }
                    if domain.volumeSize > 0 {
                        labeledRow("Volume Size") {
                            Text("\(domain.volumeSize) GB")
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Cluster Health

    private var clusterHealthSection: some View {
        GroupBox("Cluster Health") {
            VStack(alignment: .leading, spacing: 8) {
                if domain.endpoint.isEmpty {
                    Text("Cluster endpoint not available")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if isLoadingCluster {
                    ProgressView()
                        .controlSize(.small)
                } else if let health = clusterHealth {
                    labeledRow("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(healthColor(health.status))
                                .frame(width: 10, height: 10)
                            Text(health.status.capitalized)
                                .fontWeight(.medium)
                        }
                    }
                    if !health.clusterName.isEmpty {
                        labeledRow("Cluster Name") {
                            Text(health.clusterName)
                                .font(.body.monospaced())
                        }
                    }
                    labeledRow("Nodes") {
                        Text(String(health.numberOfNodes))
                    }
                    labeledRow("Active Shards") {
                        Text(String(health.activeShards))
                    }
                    if health.relocatingShards > 0 {
                        labeledRow("Relocating") {
                            Text(String(health.relocatingShards))
                        }
                    }
                    if health.initializingShards > 0 {
                        labeledRow("Initializing") {
                            Text(String(health.initializingShards))
                        }
                    }
                    if health.unassignedShards > 0 {
                        labeledRow("Unassigned") {
                            Text(String(health.unassignedShards))
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Could not reach cluster")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(4)
        }
    }

    private func healthColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        default: .gray
        }
    }

    // MARK: - Indices

    private var indicesSection: some View {
        GroupBox("Indices") {
            VStack(alignment: .leading, spacing: 8) {
                if domain.endpoint.isEmpty {
                    Text("Cluster endpoint not available")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if isLoadingCluster {
                    ProgressView()
                        .controlSize(.small)
                } else if indices.isEmpty {
                    Text("No indices")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                            Text("Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                            Text("Docs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                            Text("Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.semibold)
                        }
                        Divider()
                        ForEach(indices) { index in
                            GridRow {
                                Text(index.name)
                                    .font(.body.monospaced())
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(healthColor(index.health))
                                        .frame(width: 8, height: 8)
                                    Text(index.health)
                                        .font(.caption)
                                }
                                Text(index.docCount)
                                    .monospacedDigit()
                                Text(index.storeSize)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }

    private func boolBadge(_ value: Bool) -> some View {
        Text(value ? "Yes" : "No")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background((value ? Color.green : Color.gray).opacity(0.15), in: Capsule())
            .foregroundStyle(value ? .green : .gray)
    }

    private func loadClusterData() async {
        guard !domain.endpoint.isEmpty else { return }
        isLoadingCluster = true
        do {
            async let healthResult = service.fetchClusterHealth(endpoint: domain.endpoint)
            async let indicesResult = service.fetchIndices(endpoint: domain.endpoint)
            clusterHealth = try await healthResult
            indices = try await indicesResult
        } catch {
            clusterHealth = nil
            indices = []
        }
        isLoadingCluster = false
    }

    private func deleteDomain(_ target: OpenSearchDomain) {
        Task {
            do {
                try await service.deleteDomain(name: target.domainName)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
