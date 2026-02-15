import SwiftUI
import AppKit

struct RedshiftClusterDetailPaneView: View {
    @ObservedObject var service: RedshiftService
    let cluster: RedshiftCluster
    @ObservedObject var toolbarState: RedshiftToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var serviceError: ServiceError?
    @State private var clustersToDelete: [RedshiftCluster] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                connectionSection
                configurationSection
                metadataSection
            }
            .padding(16)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .deleteCluster:
                toolbarState.pendingAction = nil
                clustersToDelete = [cluster]
            case .createCluster:
                break // handled by list view
            }
        }
        .alert(
            "Delete Cluster",
            isPresented: Binding(
                get: { !clustersToDelete.isEmpty },
                set: { if !$0 { clustersToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let target = clustersToDelete.first {
                    deleteCluster(target)
                }
            }
            Button("Cancel", role: .cancel) {
                clustersToDelete = []
            }
        } message: {
            if let target = clustersToDelete.first {
                Text("Are you sure you want to delete cluster \"\(target.clusterIdentifier)\"?\n\nThe final snapshot will be skipped.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Text(cluster.clusterIdentifier)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)
            statusBadge
            nodeTypeBadge
        }
    }

    private var statusBadge: some View {
        Text(cluster.clusterStatus)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch cluster.clusterStatus {
        case "available": .green
        case "creating", "modifying": .blue
        case "deleting": .red
        case "paused": .orange
        default: .gray
        }
    }

    private var nodeTypeBadge: some View {
        Text(cluster.nodeType)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                if !cluster.endpointAddress.isEmpty {
                    labeledRow("Endpoint") {
                        CopyableValue(text: cluster.endpointString, monospaced: true)
                    }
                } else {
                    labeledRow("Endpoint") {
                        Text("Not available")
                            .foregroundStyle(.secondary)
                    }
                }
                labeledRow("Database") {
                    Text(cluster.dbName)
                        .font(.body.monospaced())
                }
                labeledRow("Port") {
                    Text(String(cluster.endpointPort))
                        .font(.body.monospaced())
                }
                labeledRow("Username") {
                    Text(cluster.masterUsername)
                        .font(.body.monospaced())
                }
            }
            .padding(4)
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Node Type") {
                    Text(cluster.nodeType)
                        .font(.body.monospaced())
                }
                labeledRow("Nodes") {
                    Text(String(cluster.numberOfNodes))
                }
                if !cluster.clusterVersion.isEmpty {
                    labeledRow("Version") {
                        Text(cluster.clusterVersion)
                    }
                }
                labeledRow("Encrypted") {
                    boolBadge(cluster.encrypted)
                }
                labeledRow("Public") {
                    boolBadge(cluster.publiclyAccessible)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        GroupBox("Metadata") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Identifier") {
                    CopyableValue(text: cluster.clusterIdentifier, monospaced: true)
                }
                if !cluster.createTime.isEmpty {
                    labeledRow("Created") {
                        Text(cluster.createTime)
                            .foregroundStyle(.secondary)
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
                .frame(width: 80, alignment: .trailing)
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

    private func deleteCluster(_ target: RedshiftCluster) {
        Task {
            do {
                try await service.deleteCluster(id: target.clusterIdentifier)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
