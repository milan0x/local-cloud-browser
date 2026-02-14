import SwiftUI

struct SNSPublishMessageView: View {
    @ObservedObject var service: SNSService
    let topic: SNSTopic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var messageBody = ""
    @State private var subject = ""
    @State private var messageGroupId = ""
    @State private var messageDeduplicationId = ""
    @State private var serviceError: ServiceError?
    @State private var isPublishing = false
    @State private var published = false
    @State private var showJsonHelper = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Options") {
                    LabeledContent("Subject") {
                        TextField("", text: $subject, prompt: Text("Optional subject line"))
                            .multilineTextAlignment(.trailing)
                    }
                }

                if topic.isFifo {
                    Section("FIFO Settings") {
                        LabeledContent("Group ID") {
                            TextField("", text: $messageGroupId, prompt: Text("Enter message group ID"))
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Deduplication ID") {
                            TextField("", text: $messageDeduplicationId, prompt: Text("Enter deduplication ID (optional)"))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                JSONInputSection(text: $messageBody, isHelperShown: $showJsonHelper, config: .messageBody)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if published {
                    Label("Published", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("Publish") { publish() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isPublishing)
            }
            .padding()
        }
        .frame(width: 500, height: showJsonHelper ? 750 : 550)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        guard !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if topic.isFifo && messageGroupId.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func publish() {
        isPublishing = true
        serviceError = nil
        Task {
            do {
                let groupId = topic.isFifo ? messageGroupId.trimmingCharacters(in: .whitespaces) : nil
                let dedupId = topic.isFifo && !messageDeduplicationId.trimmingCharacters(in: .whitespaces).isEmpty
                    ? messageDeduplicationId.trimmingCharacters(in: .whitespaces) : nil
                let subj = subject.trimmingCharacters(in: .whitespaces)
                _ = try await service.publish(
                    topicArn: topic.topicArn,
                    message: messageBody,
                    subject: subj.isEmpty ? nil : subj,
                    messageGroupId: groupId,
                    messageDeduplicationId: dedupId
                )
                published = true
                try? await Task.sleep(for: .seconds(0.6))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isPublishing = false
            }
        }
    }
}
