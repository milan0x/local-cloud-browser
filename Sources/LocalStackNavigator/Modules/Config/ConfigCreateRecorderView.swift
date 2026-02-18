import SwiftUI

struct ConfigCreateRecorderView: View {
    @ObservedObject var service: ConfigService
    var onCreate: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var roleARN = ""
    @State private var allSupported = true
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Recorder Name", text: $name)
                TextField("Role ARN", text: $roleARN)
                Toggle("Record all supported resources", isOn: $allSupported)
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
        .frame(width: 420)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !roleARN.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let recorderName = name.trimmingCharacters(in: .whitespaces)
                try await service.putConfigurationRecorder(
                    name: recorderName,
                    roleARN: roleARN.trimmingCharacters(in: .whitespaces),
                    allSupported: allSupported,
                    resourceTypes: []
                )
                onCreate?(recorderName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
