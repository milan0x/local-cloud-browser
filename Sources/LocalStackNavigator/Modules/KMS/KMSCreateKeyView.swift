import SwiftUI

struct KMSCreateKeyView: View {
    @ObservedObject var service: KMSService
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var keyUsage = "ENCRYPT_DECRYPT"
    @State private var keySpec = "SYMMETRIC_DEFAULT"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let keyUsages = ["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC"]
    private let keySpecs = [
        "SYMMETRIC_DEFAULT",
        "RSA_2048", "RSA_3072", "RSA_4096",
        "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521", "ECC_SECG_P256K1",
        "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Description (optional)", text: $description)

                Picker("Key Usage", selection: $keyUsage) {
                    ForEach(keyUsages, id: \.self) { usage in
                        Text(usage).tag(usage)
                    }
                }

                Picker("Key Spec", selection: $keySpec) {
                    ForEach(keySpecs, id: \.self) { spec in
                        Text(spec).tag(spec)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createKey(
                    description: description.trimmingCharacters(in: .whitespaces),
                    keyUsage: keyUsage,
                    keySpec: keySpec
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
