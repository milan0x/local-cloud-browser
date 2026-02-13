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

                Section {
                    ZStack(alignment: .topLeading) {
                        CodeTextEditor(text: $messageBody)
                    }
                    .frame(minHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                } header: {
                    messageBodyHeader
                }
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
        .frame(width: 500, height: 550)
        .serviceErrorAlert(error: $serviceError)
    }

    @ViewBuilder
    private var messageBodyHeader: some View {
        HStack(spacing: 6) {
            Text("Message Body")
            if let type = detectedBodyType {
                Text(type)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(bodyTypeBadgeColor(type), in: Capsule())
                    .foregroundStyle(bodyTypeForegroundColor(type))
            }
        }
        .frame(height: 18, alignment: .leading)
    }

    private var detectedBodyType: String? {
        let trimmed = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return "JSON"
        } else if trimmed.hasPrefix("<") {
            return "XML"
        }
        return "Text"
    }

    private func bodyTypeBadgeColor(_ type: String) -> Color {
        switch type {
        case "JSON": return Color.blue.opacity(0.15)
        case "XML": return Color.orange.opacity(0.15)
        default: return Color.gray.opacity(0.15)
        }
    }

    private func bodyTypeForegroundColor(_ type: String) -> Color {
        switch type {
        case "JSON": return .blue
        case "XML": return .orange
        default: return .secondary
        }
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
