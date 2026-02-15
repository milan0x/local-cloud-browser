import SwiftUI

struct SupportCreateCaseView: View {
    @ObservedObject var service: SupportService
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var communicationBody = ""
    @State private var serviceCode = ""
    @State private var categoryCode = ""
    @State private var severityCode = "normal"
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    @State private var hasAttemptedCreate = false

    private let severityLevels = ["low", "normal", "high", "urgent", "critical"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Case Details") {
                    TextField("Subject", text: $subject)
                    if hasAttemptedCreate && subject.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Subject is required")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Severity", selection: $severityCode) {
                        ForEach(severityLevels, id: \.self) { level in
                            Text(level.capitalized).tag(level)
                        }
                    }
                }

                Section("Classification (Optional)") {
                    TextField("Service Code", text: $serviceCode, prompt: Text("e.g. amazon-s3"))
                    TextField("Category Code", text: $categoryCode, prompt: Text("e.g. general-guidance"))
                }

                Section("Communication") {
                    TextEditor(text: $communicationBody)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    if hasAttemptedCreate && communicationBody.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Communication body is required")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("LocalStack Mock Limitations")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        Text("• Severity may not be respected by LocalStack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• \"Submitted By\" is auto-assigned and cannot be changed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("• Cases may not persist across container restarts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Case") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 480)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        let trimmedBody = communicationBody.trimmingCharacters(in: .whitespaces)
        return !trimmedSubject.isEmpty && !trimmedBody.isEmpty
    }

    private func save() {
        hasAttemptedCreate = true
        guard isValid else { return }

        isSaving = true
        serviceError = nil
        let trimmedSubject = subject.trimmingCharacters(in: .whitespaces)
        let trimmedBody = communicationBody.trimmingCharacters(in: .whitespaces)
        let trimmedService = serviceCode.trimmingCharacters(in: .whitespaces)
        let trimmedCategory = categoryCode.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                _ = try await service.createCase(
                    subject: trimmedSubject,
                    serviceCode: trimmedService,
                    severityCode: severityCode,
                    categoryCode: trimmedCategory,
                    communicationBody: trimmedBody
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
