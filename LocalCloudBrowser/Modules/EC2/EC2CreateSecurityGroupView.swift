import SwiftUI

struct EC2CreateSecurityGroupView: View {
    @ObservedObject var service: EC2Service
    @Environment(\.dismiss) private var dismiss
    var existingNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var vpcId = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var hasAttemptedCreate = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Group Name", text: $groupName)
                TextField("Description", text: $groupDescription)
                TextField("VPC ID (optional)", text: $vpcId)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A security group named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            if hasAttemptedCreate && trimmedDescription.isEmpty {
                Text("Description is required")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .frame(minHeight: 260)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedName: String {
        groupName.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedDescription: String {
        groupDescription.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingNames.contains(trimmedName)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists && !trimmedDescription.isEmpty
    }

    private func save() {
        hasAttemptedCreate = true
        guard isValid else { return }
        isSaving = true
        serviceError = nil
        Task {
            do {
                let vpc = vpcId.trimmingCharacters(in: .whitespaces)
                _ = try await service.createSecurityGroup(
                    name: trimmedName,
                    description: trimmedDescription,
                    vpcId: vpc.isEmpty ? nil : vpc
                )
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
