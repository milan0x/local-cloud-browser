import SwiftUI
import AppKit

struct EC2InstanceDetailView: View {
    @ObservedObject var service: EC2Service
    let instanceId: String
    @EnvironmentObject private var appState: AppState

    @State private var instance: EC2Instance?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            if isLoading && instance == nil {
                ProgressView("Loading instance...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let instance {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        instanceInfoSection(instance)
                        instanceActionsSection(instance)
                        if !instance.securityGroups.isEmpty {
                            securityGroupsSection(instance)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Instance not found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadInstance() }
        .onChange(of: instanceId) {
            instance = nil
            loadInstance()
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(instance?.displayName ?? instanceId)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if let state = instance?.state {
                        stateBadge(state)
                    }
                }
                Text("Instance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stateBadge(_ state: EC2InstanceState) -> some View {
        Text(state.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(state.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(state.color)
    }

    // MARK: - Instance Info

    @ViewBuilder
    private func instanceInfoSection(_ inst: EC2Instance) -> some View {
        GroupBox("Instance Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Instance ID") {
                    CopyableValue(text: inst.instanceId, monospaced: true)
                }
                LabeledContent("Image ID") {
                    CopyableValue(text: inst.imageId, monospaced: true)
                }
                LabeledContent("Instance Type") {
                    Text(inst.instanceType)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("State") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(inst.state.color)
                            .frame(width: 8, height: 8)
                        Text(inst.state.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
                if let ip = inst.privateIpAddress {
                    LabeledContent("Private IP") {
                        CopyableValue(text: ip, monospaced: true)
                    }
                }
                if let ip = inst.publicIpAddress {
                    LabeledContent("Public IP") {
                        CopyableValue(text: ip, monospaced: true)
                    }
                }
                if let az = inst.availabilityZone {
                    LabeledContent("Availability Zone") {
                        Text(az).foregroundStyle(.secondary)
                    }
                }
                if let key = inst.keyName {
                    LabeledContent("Key Name") {
                        CopyableValue(text: key)
                    }
                }
                if let launched = inst.launchTime {
                    LabeledContent("Launch Time") {
                        CopyableValue(text: Self.dateFormatter.string(from: launched))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func instanceActionsSection(_ inst: EC2Instance) -> some View {
        GroupBox("Actions") {
            HStack(spacing: 12) {
                Button("Start") {
                    performAction { try await service.startInstances([inst.instanceId]) }
                }
                .disabled(!inst.state.canStart || appState.isReadOnly)

                Button("Stop") {
                    performAction { try await service.stopInstances([inst.instanceId]) }
                }
                .disabled(!inst.state.canStop || appState.isReadOnly)

                Button("Reboot") {
                    performAction { try await service.rebootInstances([inst.instanceId]) }
                }
                .disabled(!inst.state.canReboot || appState.isReadOnly)

                Button("Terminate") {
                    performAction { try await service.terminateInstances([inst.instanceId]) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!inst.state.canTerminate || appState.isReadOnly)

                Spacer()
            }
            .padding(4)
        }
    }

    // MARK: - Security Groups

    @ViewBuilder
    private func securityGroupsSection(_ inst: EC2Instance) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(inst.securityGroups) { sg in
                    HStack {
                        Text(sg.groupName)
                            .fontWeight(.medium)
                        Text(sg.groupId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    .contextMenu {
                        Button("Copy Group ID") { copyToClipboard(sg.groupId) }
                        Button("Copy Group Name") { copyToClipboard(sg.groupName) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack {
                Text("Security Groups")
                Text("(\(inst.securityGroups.count))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    private func loadInstance() {
        isLoading = true
        Task {
            do {
                let all = try await service.listInstances()
                instance = all.first { $0.instanceId == instanceId }
            } catch {
                serviceError = error.asServiceError
            }
            isLoading = false
        }
    }

    private func performAction(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                // Reload after action
                try? await Task.sleep(nanoseconds: 500_000_000)
                loadInstance()
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
