import SwiftUI

struct CloudFormationCreateStackView: View {
    @ObservedObject var service: CloudFormationService
    @Environment(\.dismiss) private var dismiss
    @State private var stackName = ""
    @State private var templateBody = ""
    @State private var parameters: [ParameterRow] = []
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingStackNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    struct ParameterRow: Identifiable {
        let id = UUID()
        var key: String = ""
        var value: String = ""
    }

    private static let namePattern = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9-]*$")

    var body: some View {
        CreateFormScaffold(
            width: 520,
            minHeight: 480,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Stack") {
                    TextField("Stack name", text: $stackName)
                }

                JSONInputSection(text: $templateBody, config: .templateBody)

                Section("Parameters") {
                    ForEach($parameters) { $row in
                        HStack {
                            TextField("Key", text: $row.key)
                                .frame(maxWidth: .infinity)
                            TextField("Value", text: $row.value)
                                .frame(maxWidth: .infinity)
                            Button {
                                parameters.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        parameters.append(ParameterRow())
                    } label: {
                        Label("Add Parameter", systemImage: "plus")
                    }
                }

            if nameExists {
                Text("A stack named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must start with a letter and contain only letters, numbers, and hyphens.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var trimmedName: String {
        stackName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingStackNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && !nameExists
            && nameMatchesPattern
            && !templateBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        let cfParams = parameters
            .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { CFParameter(parameterKey: $0.key.trimmingCharacters(in: .whitespaces), parameterValue: $0.value) }
        Task {
            do {
                try await service.createStack(
                    name: trimmedName,
                    templateBody: templateBody,
                    parameters: cfParams
                )
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
