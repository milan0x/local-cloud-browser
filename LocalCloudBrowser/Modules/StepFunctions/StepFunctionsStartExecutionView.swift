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
        CreateFormScaffold(
            width: 520,
            isValid: true,
            isCreating: isSaving,
            createLabel: "Start Execution",
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Execution Name (optional)", text: $name)
                    .help("Leave empty for auto-generated name")

                JSONInputSection(text: $input, isHelperShown: $showJsonHelper, config: .executionInput)
        }
        .frame(minHeight: showJsonHelper ? 620 : 420)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
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
