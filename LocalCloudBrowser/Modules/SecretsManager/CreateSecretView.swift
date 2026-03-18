import SwiftUI

struct CreateSecretView: View {
    @ObservedObject var service: SecretsManagerService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var secretName = ""
    @State private var secretDescription = ""
    @State private var secretValue = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingSecretNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    // Edit mode
    var editingSecret: Secret?
    var editingValue: String?

    private var isEditing: Bool { editingSecret != nil }

    init(service: SecretsManagerService, existingSecretNames: Set<String>, onCreate: ((String) -> Void)? = nil, editingSecret: Secret? = nil, editingValue: String? = nil) {
        self.service = service
        self.existingSecretNames = existingSecretNames
        self.onCreate = onCreate
        self.editingSecret = editingSecret
        self.editingValue = editingValue
        _secretName = State(initialValue: editingSecret?.name ?? "")
        _secretDescription = State(initialValue: editingSecret?.description ?? "")
        _secretValue = State(initialValue: editingValue ?? "")
    }

    var body: some View {
        CreateFormScaffold(
            width: 480,
            minHeight: 400,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: isEditing ? "Update" : "Create",
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Secret name", text: $secretName)
                    .disabled(isEditing)

                TextField("Description (optional)", text: $secretDescription)

                JSONInputSection(text: $secretValue, config: .secretValue)

            if nameExists {
                Text("A secret named \"\(secretName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var nameExists: Bool {
        let name = secretName.trimmingCharacters(in: .whitespaces)
        return !isEditing && !name.isEmpty && existingSecretNames.contains(name)
    }

    private var isValid: Bool {
        let name = secretName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        guard !secretValue.isEmpty else { return false }
        return !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let name = secretName.trimmingCharacters(in: .whitespaces)
                let desc = secretDescription.trimmingCharacters(in: .whitespaces)
                if isEditing, let secret = editingSecret {
                    try await service.updateSecret(
                        secretId: secret.arn,
                        secretString: secretValue,
                        description: desc.isEmpty ? nil : desc
                    )
                } else {
                    try await service.createSecret(
                        name: name,
                        secretString: secretValue,
                        description: desc.isEmpty ? nil : desc
                    )
                    licenseManager.incrementCreateCount(for: .secretsManager)
                    onCreate?(name)
                }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
