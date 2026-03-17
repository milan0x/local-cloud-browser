import SwiftUI

struct SESVerifyIdentityView: View {
    @ObservedObject var service: SESService
    let existingIdentities: [String]
    var onCreate: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var identityType = "Email"
    @State private var identityValue = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let identityTypes = ["Email", "Domain"]

    var body: some View {
        CreateFormScaffold(
            width: 400,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: "Verify",
            serviceError: $serviceError,
            onCreate: verify
        ) {
            Picker("Type", selection: $identityType) {
                ForEach(identityTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                identityType == "Email" ? "Email address" : "Domain name",
                text: $identityValue,
                prompt: Text(identityType == "Email" ? "user@example.com" : "example.com")
            )

            if isDuplicate {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("This identity already exists")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var trimmedValue: String {
        identityValue.trimmingCharacters(in: .whitespaces)
    }

    private var isDuplicate: Bool {
        !trimmedValue.isEmpty && existingIdentities.contains(trimmedValue)
    }

    private var isValid: Bool {
        guard !trimmedValue.isEmpty && !isDuplicate else { return false }
        if identityType == "Email" {
            return trimmedValue.contains("@") && trimmedValue.contains(".")
        }
        return trimmedValue.contains(".")
    }

    private func verify() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                if identityType == "Email" {
                    try await service.verifyEmailIdentity(email: trimmedValue)
                } else {
                    try await service.verifyDomainIdentity(domain: trimmedValue)
                }
                onCreate?(trimmedValue)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
