import SwiftUI

struct CreateSecretView: View {
    @ObservedObject var service: SecretsManagerService
    @Environment(\.dismiss) private var dismiss
    @State private var secretName = ""
    @State private var secretDescription = ""
    @State private var secretValue = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingSecretNames: Set<String>

    // Edit mode
    var editingSecret: Secret?
    var editingValue: String?

    private var isEditing: Bool { editingSecret != nil }

    init(service: SecretsManagerService, existingSecretNames: Set<String>, editingSecret: Secret? = nil, editingValue: String? = nil) {
        self.service = service
        self.existingSecretNames = existingSecretNames
        self.editingSecret = editingSecret
        self.editingValue = editingValue
        _secretName = State(initialValue: editingSecret?.name ?? "")
        _secretDescription = State(initialValue: editingSecret?.description ?? "")
        _secretValue = State(initialValue: editingValue ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Secret name", text: $secretName)
                    .disabled(isEditing)

                TextField("Description (optional)", text: $secretDescription)

                Section("Secret Value") {
                    CodeTextEditor(text: $secretValue, isEditable: true)
                        .frame(minHeight: 150)
                        .disableSmartSubstitutions()
                }

                if !secretValue.isEmpty {
                    Section {
                        HStack {
                            Text("Detected type:")
                                .foregroundStyle(.secondary)
                            Text(detectedType)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(typeColor)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A secret named \"\(secretName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Update" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var detectedType: String {
        let trimmed = secretValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "JSON"
        }
        return "Text"
    }

    private var typeColor: Color {
        detectedType == "JSON" ? .blue : .gray
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
                if isEditing {
                    try await service.updateSecret(
                        secretId: editingSecret!.arn,
                        secretString: secretValue,
                        description: desc.isEmpty ? nil : desc
                    )
                } else {
                    try await service.createSecret(
                        name: name,
                        secretString: secretValue,
                        description: desc.isEmpty ? nil : desc
                    )
                }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
