import SwiftUI
import AppKit

struct EC2SecurityGroupDetailView: View {
    @ObservedObject var service: EC2Service
    let groupId: String
    @EnvironmentObject private var appState: AppState

    @State private var securityGroup: EC2SecurityGroup?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?
    @State private var showAddInboundRuleSheet = false
    @State private var showAddOutboundRuleSheet = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()

            if isLoading && securityGroup == nil {
                ProgressView("Loading security group...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let sg = securityGroup {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sgInfoSection(sg)
                        inboundRulesSection(sg)
                        outboundRulesSection(sg)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "shield")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Security group not found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAddInboundRuleSheet) {
            if let sg = securityGroup {
                EC2AddRuleView(service: service, groupId: sg.groupId, direction: .inbound)
                    .onDisappear { loadSecurityGroup() }
            }
        }
        .sheet(isPresented: $showAddOutboundRuleSheet) {
            if let sg = securityGroup {
                EC2AddRuleView(service: service, groupId: sg.groupId, direction: .outbound)
                    .onDisappear { loadSecurityGroup() }
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadSecurityGroup() }
        .onChange(of: groupId) {
            securityGroup = nil
            loadSecurityGroup()
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(securityGroup?.groupName ?? groupId)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("Security Group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Info

    @ViewBuilder
    private func sgInfoSection(_ sg: EC2SecurityGroup) -> some View {
        GroupBox("Security Group Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Group ID") {
                    CopyableValue(text: sg.groupId, monospaced: true)
                }
                LabeledContent("Group Name") {
                    CopyableValue(text: sg.groupName)
                }
                LabeledContent("Description") {
                    Text(sg.groupDescription)
                        .foregroundStyle(.secondary)
                }
                if let vpc = sg.vpcId {
                    LabeledContent("VPC ID") {
                        CopyableValue(text: vpc, monospaced: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Inbound Rules

    @ViewBuilder
    private func inboundRulesSection(_ sg: EC2SecurityGroup) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if sg.inboundRules.isEmpty {
                    Text("No inbound rules")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                } else {
                    rulesHeader
                    ForEach(sg.inboundRules) { rule in
                        ruleRow(rule, direction: .inbound, sg: sg)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text("Inbound Rules")
                Text("(\(sg.inboundRules.count))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddInboundRuleSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Add Inbound Rule")
            }
        }
    }

    // MARK: - Outbound Rules

    @ViewBuilder
    private func outboundRulesSection(_ sg: EC2SecurityGroup) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if sg.outboundRules.isEmpty {
                    Text("No outbound rules")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                } else {
                    rulesHeader
                    ForEach(sg.outboundRules) { rule in
                        ruleRow(rule, direction: .outbound, sg: sg)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text("Outbound Rules")
                Text("(\(sg.outboundRules.count))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddOutboundRuleSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Add Outbound Rule")
            }
        }
    }

    // MARK: - Rules Table

    private var rulesHeader: some View {
        HStack(spacing: 0) {
            Text("Protocol")
                .frame(width: 90, alignment: .leading)
            Text("Port Range")
                .frame(width: 80, alignment: .leading)
            Text("Source/Dest")
                .frame(minWidth: 100, alignment: .leading)
            Text("Description")
                .frame(minWidth: 80, alignment: .leading)
            Spacer()
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func ruleRow(_ rule: EC2SecurityGroupRule, direction: EC2RuleDirection, sg: EC2SecurityGroup) -> some View {
        Divider()
        HStack(spacing: 0) {
            Text(rule.protocolDisplay)
                .frame(width: 90, alignment: .leading)
            Text(rule.portRangeDisplay)
                .frame(width: 80, alignment: .leading)
            Text(rule.cidrIp.isEmpty ? "N/A" : rule.cidrIp)
                .frame(minWidth: 100, alignment: .leading)
                .lineLimit(1)
            Text(rule.description ?? "")
                .foregroundStyle(.secondary)
                .frame(minWidth: 80, alignment: .leading)
                .lineLimit(1)
            Spacer()
            Button {
                revokeRule(rule, direction: direction, groupId: sg.groupId)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(appState.isReadOnly ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)
            .help("Remove Rule")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Source/Dest") { copyToClipboard(rule.cidrIp) }
            Divider()
            Button("Remove Rule", role: .destructive) {
                revokeRule(rule, direction: direction, groupId: sg.groupId)
            }
            .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Data

    private func loadSecurityGroup() {
        isLoading = true
        Task {
            do {
                let all = try await service.listSecurityGroups()
                securityGroup = all.first { $0.groupId == groupId }
            } catch {
                serviceError = error.asServiceError
            }
            isLoading = false
        }
    }

    private func revokeRule(_ rule: EC2SecurityGroupRule, direction: EC2RuleDirection, groupId: String) {
        Task {
            do {
                switch direction {
                case .inbound:
                    try await service.revokeSecurityGroupIngress(
                        groupId: groupId,
                        ipProtocol: rule.ipProtocol,
                        fromPort: rule.fromPort,
                        toPort: rule.toPort,
                        cidrIp: rule.cidrIp
                    )
                case .outbound:
                    try await service.revokeSecurityGroupEgress(
                        groupId: groupId,
                        ipProtocol: rule.ipProtocol,
                        fromPort: rule.fromPort,
                        toPort: rule.toPort,
                        cidrIp: rule.cidrIp
                    )
                }
                loadSecurityGroup()
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
