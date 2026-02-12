import SwiftUI

struct SQSSendMessageView: View {
    @ObservedObject var service: SQSService
    let queue: SQSQueue
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var messageBody = ""
    @State private var delaySeconds = ""
    @State private var messageGroupId = ""
    @State private var messageDeduplicationId = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Message Body") {
                    TextEditor(text: $messageBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                }

                Section("Options") {
                    TextField("Delay (seconds, 0-900)", text: $delaySeconds)
                        .help("Number of seconds to delay the message (0-900)")
                }

                if queue.isFifo {
                    Section("FIFO Settings") {
                        TextField("Message Group ID (required)", text: $messageGroupId)
                        TextField("Deduplication ID (optional)", text: $messageDeduplicationId)
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSending)
            }
            .padding()
        }
        .frame(width: 450, height: 380)
    }

    private var isValid: Bool {
        guard !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let delay = Int(delaySeconds), (delay < 0 || delay > 900) { return false }
        if !delaySeconds.isEmpty && Int(delaySeconds) == nil { return false }
        if queue.isFifo && messageGroupId.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                let delay = Int(delaySeconds)
                let groupId = queue.isFifo ? messageGroupId.trimmingCharacters(in: .whitespaces) : nil
                let dedupId = queue.isFifo && !messageDeduplicationId.trimmingCharacters(in: .whitespaces).isEmpty
                    ? messageDeduplicationId.trimmingCharacters(in: .whitespaces) : nil
                _ = try await service.sendMessage(
                    queueUrl: queue.queueUrl,
                    body: messageBody,
                    delaySeconds: delay,
                    messageGroupId: groupId,
                    messageDeduplicationId: dedupId
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
