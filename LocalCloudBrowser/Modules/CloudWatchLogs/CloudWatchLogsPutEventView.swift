import SwiftUI

struct CloudWatchLogsPutEventView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroupName: String
    let logStreamName: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var message = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        CreateFormScaffold(
            width: 480,
            minHeight: 380,
            isValid: isValid && !appState.isReadOnly,
            isCreating: isSaving,
            createLabel: "Write Event",
            serviceError: $serviceError,
            onCreate: save
        ) {
                LabeledContent("Log Group") {
                    Text(logGroupName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                LabeledContent("Log Stream") {
                    Text(logStreamName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                JSONInputSection(text: $message, config: .logMessage)
        }
    }

    private var isValid: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.putLogEvents(
                    logGroupName: logGroupName,
                    logStreamName: logStreamName,
                    message: message
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
