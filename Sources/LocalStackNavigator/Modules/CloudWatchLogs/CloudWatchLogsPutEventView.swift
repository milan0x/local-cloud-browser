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
        VStack(spacing: 0) {
            Form {
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

                Section("Message") {
                    CodeTextEditor(text: $message, isEditable: true)
                        .frame(minHeight: 200)
                        .disableSmartSubstitutions()
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Write Event") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving || appState.isReadOnly)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: 380)
        .serviceErrorAlert(error: $serviceError)
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
