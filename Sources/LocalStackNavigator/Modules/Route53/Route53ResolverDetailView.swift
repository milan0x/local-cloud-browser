import SwiftUI

struct Route53ResolverDetailView: View {
    @ObservedObject var service: Route53ResolverService
    let endpoint: ResolverEndpoint

    @State private var ipAddresses: [ResolverIpAddress] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && ipAddresses.isEmpty {
                ProgressView("Loading endpoint details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, ipAddresses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadDetail() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailContent
            }
        }
        .task(id: endpoint.id) {
            await loadDetail()
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                endpointInfoSection
                ipAddressesSection
            }
            .padding()
        }
    }

    private var endpointInfoSection: some View {
        GroupBox("Endpoint Info") {
            VStack(spacing: 6) {
                labeledRow("Name", endpoint.name)
                labeledRow("ID", endpoint.id)
                labeledRow("ARN", endpoint.arn)
                HStack {
                    Text("Direction")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    directionBadge(endpoint.direction)
                    Spacer()
                }
                HStack {
                    Text("Status")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    statusBadge(endpoint.status)
                    Spacer()
                }
                if !endpoint.statusMessage.isEmpty {
                    labeledRow("Status Message", endpoint.statusMessage)
                }
                labeledRow("VPC", endpoint.hostVPCId)
                labeledRow("IP Addresses", "\(endpoint.ipAddressCount)")
                if !endpoint.creationTime.isEmpty {
                    labeledRow("Created", endpoint.creationTime)
                }
                if !endpoint.modificationTime.isEmpty {
                    labeledRow("Modified", endpoint.modificationTime)
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
        }
    }

    private var ipAddressesSection: some View {
        GroupBox("IP Addresses (\(ipAddresses.count))") {
            if ipAddresses.isEmpty {
                Text("No IP addresses")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(ipAddresses) { addr in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(addr.ip.isEmpty ? "(auto-assigned)" : addr.ip)
                                    .font(.caption)
                                    .monospaced()
                                    .fontWeight(.medium)
                                Text("Subnet: \(addr.subnetId)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ipStatusBadge(addr.status)
                        }
                        .padding(.vertical, 2)
                        if addr.id != ipAddresses.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func statusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: endpoint.statusBadgeColor)
    }

    private func directionBadge(_ direction: String) -> some View {
        StatusBadge(text: direction, color: endpoint.directionBadgeColor)
    }

    private func ipStatusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "ATTACHED": .green
        case "CREATING", "ATTACHING": .orange
        case "DELETING", "DETACHING": .red
        case "FAILED_CREATION", "FAILED_RESOURCE_GONE": .red
        default: .gray
        }
        return StatusBadge(text: status, color: color)
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            ipAddresses = try await service.listResolverEndpointIpAddresses(endpointId: endpoint.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
