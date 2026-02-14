import SwiftUI

struct CloudWatchLogsCreateStreamView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroupName: String
    @Environment(\.dismiss) private var dismiss
    @State private var logStreamName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingStreamNames: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("Log Group") {
                    Text(logGroupName)
                        .foregroundStyle(.secondary)
                }
                TextField("Log stream name", text: $logStreamName)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A log stream named \"\(logStreamName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

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
        .frame(width: 400)
        .frame(minHeight: 180)
        .serviceErrorAlert(error: $serviceError)
    }

    private var nameExists: Bool {
        let name = logStreamName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && existingStreamNames.contains(name)
    }

    private var isValid: Bool {
        let name = logStreamName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let name = logStreamName.trimmingCharacters(in: .whitespaces)
                try await service.createLogStream(logGroupName: logGroupName, logStreamName: name)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
