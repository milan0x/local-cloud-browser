import SwiftUI
import AppKit

struct EC2CreateKeyPairView: View {
    @ObservedObject var service: EC2Service
    @Environment(\.dismiss) private var dismiss
    var existingNames: Set<String>

    @State private var keyName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var createdKeyPair: EC2CreatedKeyPair?

    var body: some View {
        if let created = createdKeyPair {
            privateKeyDisplay(created)
        } else {
            createForm
        }
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Key Name", text: $keyName)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A key pair named \"\(trimmedName)\" already exists.")
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
        .frame(minHeight: 180)
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Private Key Display

    private func privateKeyDisplay(_ kp: EC2CreatedKeyPair) -> some View {
        VStack(spacing: 0) {
            // Warning banner
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This is the only time you can view the private key. Copy or save it now.")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Key Name") {
                        Text(kp.keyName)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Key Pair ID") {
                        Text(kp.keyPairId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Fingerprint") {
                        Text(kp.keyFingerprint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Divider()

                    Text("Private Key")
                        .fontWeight(.medium)

                    Text(kp.keyMaterial)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Button("Copy Private Key") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(kp.keyMaterial, forType: .string)
                        }
                        Spacer()
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 460)
    }

    // MARK: - Helpers

    private var trimmedName: String {
        keyName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingNames.contains(trimmedName)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let result = try await service.createKeyPair(keyName: trimmedName)
                createdKeyPair = result
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
