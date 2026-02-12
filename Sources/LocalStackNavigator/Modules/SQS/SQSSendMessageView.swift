import SwiftUI

struct SQSSendMessageView: View {
    @ObservedObject var service: SQSService
    let queue: SQSQueue
    @ObservedObject var favoriteStore: SQSFavoriteStore
    var editingFavorite: SavedSQSFavorite?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var messageBody = ""
    @State private var delaySeconds = ""
    @State private var messageGroupId = ""
    @State private var messageDeduplicationId = ""
    @State private var serviceError: ServiceError?
    @State private var isSending = false
    @State private var saveAsQuickMessage = false
    @State private var quickMessageName = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if !queue.isFifo {
                    Section("Options") {
                        LabeledContent("Delay") {
                            TextField("", text: $delaySeconds, prompt: Text("0–900 seconds"))
                                .frame(width: 160)
                                .multilineTextAlignment(.trailing)
                        }
                        .help("Number of seconds to delay the message (0–900)")
                    }
                }

                if queue.isFifo {
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

                Section("Message Body") {
                    TextEditor(text: $messageBody)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                }

                Section("Quick Message") {
                    Toggle("Save as Quick Message", isOn: $saveAsQuickMessage)
                    if saveAsQuickMessage {
                        LabeledContent("Name") {
                            TextField("", text: $quickMessageName, prompt: Text("Enter a name"))
                                .multilineTextAlignment(.trailing)
                                .onChange(of: quickMessageName) {
                                    if quickMessageName.count > SavedSQSFavorite.maxNameLength {
                                        quickMessageName = String(quickMessageName.prefix(SavedSQSFavorite.maxNameLength))
                                    }
                                }
                        }
                        .help("Name shown on the quick message chip (max \(SavedSQSFavorite.maxNameLength) characters)")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if saveAsQuickMessage && !quickMessageName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(editingFavorite != nil ? "Update" : "Save") { saveFavorite() }
                        .disabled(!isBodyValid)
                }
                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSending)
            }
            .padding()
        }
        .frame(width: 500, height: 580)
        .serviceErrorAlert(error: $serviceError)
        .onAppear {
            if let fav = editingFavorite {
                messageBody = fav.messageBody
                if let delay = fav.delaySeconds {
                    delaySeconds = String(delay)
                }
                messageGroupId = fav.messageGroupId ?? ""
                messageDeduplicationId = fav.messageDeduplicationId ?? ""
                saveAsQuickMessage = true
                quickMessageName = fav.name
            }
        }
        .onChange(of: saveAsQuickMessage) {
            if saveAsQuickMessage && quickMessageName.isEmpty && editingFavorite == nil {
                prefillName()
            }
        }
        .onChange(of: messageBody) {
            if saveAsQuickMessage && quickMessageName.isEmpty && editingFavorite == nil {
                prefillName()
            }
        }
    }

    private var isBodyValid: Bool {
        !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isValid: Bool {
        guard isBodyValid else { return false }
        if !queue.isFifo {
            if let delay = Int(delaySeconds), (delay < 0 || delay > 900) { return false }
            if !delaySeconds.isEmpty && Int(delaySeconds) == nil { return false }
        }
        if queue.isFifo && messageGroupId.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func prefillName() {
        let trimmed = messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            quickMessageName = String(trimmed.prefix(SavedSQSFavorite.maxNameLength))
        }
    }

    private func saveFavorite() {
        let name = quickMessageName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let delay = queue.isFifo ? nil : Int(delaySeconds)
        let groupId = queue.isFifo ? messageGroupId.trimmingCharacters(in: .whitespaces) : nil
        let dedupId = queue.isFifo && !messageDeduplicationId.trimmingCharacters(in: .whitespaces).isEmpty
            ? messageDeduplicationId.trimmingCharacters(in: .whitespaces) : nil

        if var existing = editingFavorite {
            existing.name = name
            existing.messageBody = messageBody
            existing.delaySeconds = delay
            existing.messageGroupId = groupId
            existing.messageDeduplicationId = dedupId
            favoriteStore.update(existing)
        } else {
            let favorite = SavedSQSFavorite(
                name: name,
                queueUrl: queue.queueUrl,
                messageBody: messageBody,
                delaySeconds: delay,
                messageGroupId: groupId,
                messageDeduplicationId: dedupId
            )
            favoriteStore.add(favorite)
        }
        dismiss()
    }

    private func send() {
        isSending = true
        serviceError = nil
        Task {
            do {
                let delay = queue.isFifo ? nil : Int(delaySeconds)
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
                // Also save as favorite if toggle is on
                if saveAsQuickMessage && !quickMessageName.trimmingCharacters(in: .whitespaces).isEmpty {
                    let name = quickMessageName.trimmingCharacters(in: .whitespaces)
                    if var existing = editingFavorite {
                        existing.name = name
                        existing.messageBody = messageBody
                        existing.delaySeconds = delay
                        existing.messageGroupId = groupId
                        existing.messageDeduplicationId = dedupId
                        favoriteStore.update(existing)
                    } else {
                        let favorite = SavedSQSFavorite(
                            name: name,
                            queueUrl: queue.queueUrl,
                            messageBody: messageBody,
                            delaySeconds: delay,
                            messageGroupId: groupId,
                            messageDeduplicationId: dedupId
                        )
                        favoriteStore.add(favorite)
                    }
                }
                dismiss()
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    serviceError = ServiceError(code: "SendError", message: error.localizedDescription)
                }
                isSending = false
            }
        }
    }
}
