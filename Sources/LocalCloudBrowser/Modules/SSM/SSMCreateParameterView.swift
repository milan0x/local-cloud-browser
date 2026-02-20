import SwiftUI

struct SSMCreateParameterView: View {
    @ObservedObject var service: SSMService
    @Environment(\.dismiss) private var dismiss
    @State private var parameterName = ""
    @State private var parameterDescription = ""
    @State private var parameterValue = ""
    @State private var parameterType = "String"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var showJsonHelper = false
    var existingParameterNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    // Edit mode
    var editingParameter: SSMParameter?
    var editingValue: String?

    private var isEditing: Bool { editingParameter != nil }

    private static let parameterTypes = ["String", "StringList", "SecureString"]

    init(service: SSMService, existingParameterNames: Set<String>, onCreate: ((String) -> Void)? = nil, editingParameter: SSMParameter? = nil, editingValue: String? = nil) {
        self.service = service
        self.existingParameterNames = existingParameterNames
        self.onCreate = onCreate
        self.editingParameter = editingParameter
        self.editingValue = editingValue
        _parameterName = State(initialValue: editingParameter?.name ?? "")
        _parameterDescription = State(initialValue: editingParameter?.description ?? "")
        _parameterValue = State(initialValue: editingValue ?? "")
        _parameterType = State(initialValue: editingParameter?.type ?? "String")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Parameter name", text: $parameterName)
                    .disabled(isEditing)

                Picker("Type", selection: $parameterType) {
                    ForEach(Self.parameterTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .disabled(isEditing)

                TextField("Description (optional)", text: $parameterDescription)

                JSONInputSection(text: $parameterValue, isHelperShown: $showJsonHelper, config: .parameterValue)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A parameter named \"\(parameterName.trimmingCharacters(in: .whitespaces))\" already exists.")
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
                Button(isEditing ? "Update" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: showJsonHelper ? 600 : 400)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
        .serviceErrorAlert(error: $serviceError)
    }

    private var nameExists: Bool {
        let name = parameterName.trimmingCharacters(in: .whitespaces)
        return !isEditing && !name.isEmpty && existingParameterNames.contains(name)
    }

    private var isValid: Bool {
        let name = parameterName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        guard !parameterValue.isEmpty else { return false }
        return !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let name = parameterName.trimmingCharacters(in: .whitespaces)
                let desc = parameterDescription.trimmingCharacters(in: .whitespaces)
                try await service.putParameter(
                    name: name,
                    value: parameterValue,
                    type: parameterType,
                    description: desc.isEmpty ? nil : desc,
                    overwrite: isEditing
                )
                if !isEditing { onCreate?(name) }
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
