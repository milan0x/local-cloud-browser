import SwiftUI

struct IAMAttachPolicyView: View {
    @ObservedObject var service: IAMService
    let entityType: IAMEntityType
    let entityName: String
    let availablePolicies: [IAMPolicy]
    let alreadyAttached: Set<String>
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPolicyArn: String?
    @State private var searchText = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private var filteredPolicies: [IAMPolicy] {
        let unattached = availablePolicies.filter { !alreadyAttached.contains($0.arn) }
        guard !searchText.isEmpty else { return unattached }
        let query = searchText.lowercased()
        return unattached.filter { $0.policyName.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Attach Policy to \(entityTypeLabel)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if filteredPolicies.isEmpty && availablePolicies.isEmpty {
                VStack(spacing: 8) {
                    Text("No policies available")
                        .foregroundStyle(.secondary)
                    Text("Create a policy first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    SearchBarView(query: $searchText, placeholder: "Filter policies")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()

                    List(filteredPolicies, selection: $selectedPolicyArn) { policy in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(policy.policyName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(policy.arn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(policy.arn)
                    }
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Attach") { attach() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedPolicyArn == nil || isSaving)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var entityTypeLabel: String {
        switch entityType {
        case .users: "User"
        case .roles: "Role"
        case .policies: "Policy"
        }
    }

    private func attach() {
        guard let arn = selectedPolicyArn else { return }
        isSaving = true
        serviceError = nil
        Task {
            do {
                switch entityType {
                case .users:
                    try await service.attachUserPolicy(userName: entityName, policyArn: arn)
                case .roles:
                    try await service.attachRolePolicy(roleName: entityName, policyArn: arn)
                case .policies:
                    break
                }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
