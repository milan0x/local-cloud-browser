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
    var existingParameterNames: Set<String>

    // Edit mode
    var editingParameter: SSMParameter?
    var editingValue: String?

    private var isEditing: Bool { editingParameter != nil }

    private static let parameterTypes = ["String", "StringList", "SecureString"]

    init(service: SSMService, existingParameterNames: Set<String>, editingParameter: SSMParameter? = nil, editingValue: String? = nil) {
        self.service = service
        self.existingParameterNames = existingParameterNames
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

                Section("Parameter Value") {
                    CodeTextEditor(text: $parameterValue, isEditable: true)
                        .frame(minHeight: 150)
                        .disableSmartSubstitutions()
                }

                if !parameterValue.isEmpty {
                    Section {
                        HStack {
                            Text("Detected type:")
                                .foregroundStyle(.secondary)
                            Text(detectedType)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(detectedTypeColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(detectedTypeColor)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A parameter named \"\(parameterName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

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
        .frame(minHeight: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var detectedType: String {
        let trimmed = parameterValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "JSON"
        }
        return "Text"
    }

    private var detectedTypeColor: Color {
        detectedType == "JSON" ? .blue : .gray
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
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
