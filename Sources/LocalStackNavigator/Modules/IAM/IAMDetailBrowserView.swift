import SwiftUI
import AppKit

struct IAMDetailBrowserView: View {
    @ObservedObject var service: IAMService
    let entityType: IAMEntityType
    let entityName: String
    @EnvironmentObject private var appState: AppState

    // User detail
    @State private var attachedUserPolicies: [IAMAttachedPolicy] = []
    @State private var userGroups: [IAMGroup] = []

    // Role detail
    @State private var attachedRolePolicies: [IAMAttachedPolicy] = []
    @State private var role: IAMRole?

    // Policy detail
    @State private var policy: IAMPolicy?
    @State private var policyDocument: String = ""

    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    // Attach policy sheet
    @State private var showAttachPolicySheet = false
    @State private var allPolicies: [IAMPolicy] = []

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

            if isLoading {
                ProgressView("Loading details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch entityType {
                        case .users: userDetailContent
                        case .roles: roleDetailContent
                        case .policies: policyDetailContent
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showAttachPolicySheet) {
            IAMAttachPolicyView(
                service: service,
                entityType: entityType,
                entityName: entityName,
                availablePolicies: allPolicies,
                alreadyAttached: entityType == .users
                    ? Set(attachedUserPolicies.map(\.policyArn))
                    : Set(attachedRolePolicies.map(\.policyArn))
            )
            .onDisappear { loadDetails() }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadDetails() }
        .onChange(of: entityName) {
            attachedUserPolicies = []
            userGroups = []
            attachedRolePolicies = []
            role = nil
            policy = nil
            policyDocument = ""
            loadDetails()
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(entityType.rawValue.dropLast()) // "User", "Role", "Polic" -> need fix
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entityType == .users || entityType == .roles {
                Button {
                    loadAllPoliciesAndShowAttach()
                } label: {
                    Label("Attach Policy", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Attach Policy")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var displayName: String {
        switch entityType {
        case .users, .roles: entityName
        case .policies:
            // Show policy name from ARN
            policy?.policyName ?? entityName.components(separatedBy: "/").last ?? entityName
        }
    }

    private var entityTypeLabel: String {
        switch entityType {
        case .users: "User"
        case .roles: "Role"
        case .policies: "Policy"
        }
    }

    // MARK: - User Detail

    @ViewBuilder
    private var userDetailContent: some View {
        GroupBox("User Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("User Name") {
                    CopyableValue(text: entityName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if attachedUserPolicies.isEmpty {
                    Text("No attached policies")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(4)
                } else {
                    ForEach(attachedUserPolicies) { attached in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attached.policyName)
                                    .fontWeight(.medium)
                                Text(attached.policyArn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                detachUserPolicy(attached)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(appState.isReadOnly ? .gray : .red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(appState.isReadOnly)
                            .help("Detach Policy")
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button("Copy Policy Name") { copyToClipboard(attached.policyName) }
                            Button("Copy Policy ARN") { copyToClipboard(attached.policyArn) }
                            Divider()
                            Button("Detach", role: .destructive) { detachUserPolicy(attached) }
                                .disabled(appState.isReadOnly)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack {
                Text("Attached Policies")
                Text("(\(attachedUserPolicies.count))")
                    .foregroundStyle(.secondary)
            }
        }

        if !userGroups.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(userGroups) { group in
                        Text(group.groupName)
                            .fontWeight(.medium)
                            .contextMenu {
                                Button("Copy Group Name") { copyToClipboard(group.groupName) }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                HStack {
                    Text("Groups")
                    Text("(\(userGroups.count))")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Role Detail

    @ViewBuilder
    private var roleDetailContent: some View {
        GroupBox("Role Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Role Name") {
                    CopyableValue(text: entityName)
                }
                if let r = role {
                    if let arn = r.arn {
                        LabeledContent("ARN") {
                            CopyableValue(text: arn, monospaced: true, allowsWrapping: true)
                        }
                    }
                    if let desc = r.description, !desc.isEmpty {
                        LabeledContent("Description") {
                            Text(desc).foregroundStyle(.secondary)
                        }
                    }
                    if let created = r.createDate {
                        LabeledContent("Created") {
                            CopyableValue(text: Self.dateFormatter.string(from: created))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }

        if let trust = role?.prettyTrustPolicy {
            GroupBox("Trust Policy") {
                CodeTextEditor(text: .constant(trust), isEditable: false)
                    .frame(minHeight: 120)
            }
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if attachedRolePolicies.isEmpty {
                    Text("No attached policies")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(4)
                } else {
                    ForEach(attachedRolePolicies) { attached in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attached.policyName)
                                    .fontWeight(.medium)
                                Text(attached.policyArn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                detachRolePolicy(attached)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(appState.isReadOnly ? .gray : .red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(appState.isReadOnly)
                            .help("Detach Policy")
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button("Copy Policy Name") { copyToClipboard(attached.policyName) }
                            Button("Copy Policy ARN") { copyToClipboard(attached.policyArn) }
                            Divider()
                            Button("Detach", role: .destructive) { detachRolePolicy(attached) }
                                .disabled(appState.isReadOnly)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack {
                Text("Attached Policies")
                Text("(\(attachedRolePolicies.count))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Policy Detail

    @ViewBuilder
    private var policyDetailContent: some View {
        GroupBox("Policy Info") {
            VStack(alignment: .leading, spacing: 8) {
                if let p = policy {
                    LabeledContent("Policy Name") {
                        CopyableValue(text: p.policyName)
                    }
                    LabeledContent("ARN") {
                        CopyableValue(text: p.arn, monospaced: true, allowsWrapping: true)
                    }
                    if let desc = p.description, !desc.isEmpty {
                        LabeledContent("Description") {
                            Text(desc).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Attachments") {
                        Text("\(p.attachmentCount)")
                            .foregroundStyle(.secondary)
                    }
                    if let version = p.defaultVersionId {
                        LabeledContent("Default Version") {
                            Text(version).foregroundStyle(.secondary)
                        }
                    }
                    if let created = p.createDate {
                        LabeledContent("Created") {
                            CopyableValue(text: Self.dateFormatter.string(from: created))
                        }
                    }
                } else {
                    LabeledContent("ARN") {
                        CopyableValue(text: entityName, monospaced: true, allowsWrapping: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }

        if !policyDocument.isEmpty {
            GroupBox("Policy Document") {
                CodeTextEditor(text: .constant(policyDocument), isEditable: false)
                    .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Data

    private func loadDetails() {
        isLoading = true
        Task {
            switch entityType {
            case .users:
                do {
                    async let policies = service.listAttachedUserPolicies(userName: entityName)
                    async let groups = service.listGroupsForUser(userName: entityName)
                    attachedUserPolicies = try await policies
                    userGroups = try await groups
                } catch {
                    serviceError = error.asServiceError
                }
            case .roles:
                do {
                    async let policies = service.listAttachedRolePolicies(roleName: entityName)
                    async let roles = service.listRoles()
                    attachedRolePolicies = try await policies
                    let allRoles = try await roles
                    role = allRoles.first { $0.roleName == entityName }
                } catch {
                    serviceError = error.asServiceError
                }
            case .policies:
                do {
                    let allPolicies = try await service.listPolicies()
                    policy = allPolicies.first { $0.arn == entityName }
                    if let p = policy, let versionId = p.defaultVersionId {
                        let doc = try await service.getPolicyVersion(policyArn: p.arn, versionId: versionId)
                        // Pretty-print
                        if let data = doc.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data),
                           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                           let result = String(data: pretty, encoding: .utf8) {
                            policyDocument = result
                        } else {
                            policyDocument = doc
                        }
                    }
                } catch {
                    serviceError = error.asServiceError
                }
            }
            isLoading = false
        }
    }

    private func detachUserPolicy(_ attached: IAMAttachedPolicy) {
        Task {
            do {
                try await service.detachUserPolicy(userName: entityName, policyArn: attached.policyArn)
                attachedUserPolicies.removeAll { $0.policyArn == attached.policyArn }
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func detachRolePolicy(_ attached: IAMAttachedPolicy) {
        Task {
            do {
                try await service.detachRolePolicy(roleName: entityName, policyArn: attached.policyArn)
                attachedRolePolicies.removeAll { $0.policyArn == attached.policyArn }
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func loadAllPoliciesAndShowAttach() {
        Task {
            do {
                allPolicies = try await service.listPolicies()
            } catch {
                serviceError = error.asServiceError
                return
            }
            showAttachPolicySheet = true
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
