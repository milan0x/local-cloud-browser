import SwiftUI
import AppKit

struct OpenSearchDomainDetailView: View {
    @ObservedObject var service: OpenSearchService
    let domain: OpenSearchDomain
    @ObservedObject var toolbarState: OpenSearchToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var serviceError: ServiceError?
    @State private var domainsToDelete: [OpenSearchDomain] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                domainInfoSection
                clusterConfigSection
                storageSection
            }
            .padding(16)
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
            .background(.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(.blue)
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
