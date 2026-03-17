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
        CreateFormScaffold(
            width: 400,
            minHeight: 180,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                LabeledContent("Log Group") {
                    Text(logGroupName)
                        .foregroundStyle(.secondary)
                }
                TextField("Log stream name", text: $logStreamName)

            if nameExists {
                Text("A log stream named \"\(logStreamName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
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
