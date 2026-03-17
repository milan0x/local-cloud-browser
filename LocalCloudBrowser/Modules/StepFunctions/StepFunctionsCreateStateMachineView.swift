import SwiftUI

struct StepFunctionsCreateStateMachineView: View {
    @ObservedObject var service: StepFunctionsService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var roleArn = "arn:aws:iam::000000000000:role/StepFunctionsRole"
    @State private var type = "STANDARD"
    @State private var definition = """
    {
      "Comment": "A simple state machine",
      "StartAt": "HelloWorld",
      "States": {
        "HelloWorld": {
          "Type": "Pass",
          "Result": "Hello, World!",
          "End": true
        }
      }
    }
    """
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    var onCreate: ((String) -> Void)? = nil

    private let types = ["STANDARD", "EXPRESS"]

    var body: some View {
        CreateFormScaffold(
            width: 550,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Name", text: $name)
                TextField("Role ARN", text: $roleArn)

                Picker("Type", selection: $type) {
                    ForEach(types, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }

                JSONInputSection(text: $definition, config: .stateMachineDefinition)
        }
        .frame(height: 550)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !roleArn.trimmingCharacters(in: .whitespaces).isEmpty &&
        !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createStateMachine(
                    name: name.trimmingCharacters(in: .whitespaces),
                    definition: definition.trimmingCharacters(in: .whitespacesAndNewlines),
                    roleArn: roleArn.trimmingCharacters(in: .whitespaces),
                    type: type
                )
                licenseManager.incrementCreateCount(for: .stepFunctions)
                onCreate?(name.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
