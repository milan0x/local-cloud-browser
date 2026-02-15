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

    private let severityLevels = ["low", "normal", "high", "urgent", "critical"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Subject", text: $subject)
                    .help("Brief description of the issue")
                Picker("Severity", selection: $severityCode) {
                    ForEach(severityLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
                TextField("Service Code", text: $serviceCode)
                    .help("AWS service code (optional)")
                TextField("Category Code", text: $categoryCode)
                    .help("Category code (optional)")

                LabeledContent("Communication") {
                    TextEditor(text: $communicationBody)
                        .font(.body)
                        .frame(minHeight: 100)
                        .border(Color.secondary.opacity(0.3))
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
