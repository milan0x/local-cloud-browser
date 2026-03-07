import SwiftUI

struct StepFunctionsStartExecutionView: View {
    @ObservedObject var service: StepFunctionsService
    let stateMachineArn: String
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var input = "{}"
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    @State private var showJsonHelper = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Execution Name (optional)", text: $name)
                    .help("Leave empty for auto-generated name")

                JSONInputSection(text: $input, isHelperShown: $showJsonHelper, config: .executionInput)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start Execution") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: showJsonHelper ? 620 : 420)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
        .serviceErrorAlert(error: $serviceError)
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let trimmedName = name.trimmingCharacters(in: .whitespaces)
                let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
                try await service.startExecution(
                    stateMachineArn: stateMachineArn,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    input: trimmedInput.isEmpty ? nil : trimmedInput
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
