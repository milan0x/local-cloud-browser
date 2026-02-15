import SwiftUI

struct SESSendEmailView: View {
    @ObservedObject var service: SESService
    let prefilledFrom: String?
    @Environment(\.dismiss) private var dismiss

    @State private var from = ""
    @State private var to = ""
    @State private var cc = ""
    @State private var subject = ""
    @State private var textBody = ""
    @State private var htmlBody = ""
    @State private var bodyTab = "Text"
    @State private var serviceError: ServiceError?
    @State private var isSending = false
    @State private var sent = false

    private let bodyTabs = ["Text", "HTML"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Headers") {
                    LabeledContent("From") {
                        TextField("", text: $from, prompt: Text("sender@example.com"))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("To") {
                        TextField("", text: $to, prompt: Text("recipient@example.com (comma-separated)"))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("CC") {
                        TextField("", text: $cc, prompt: Text("Optional (comma-separated)"))
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Subject") {
                        TextField("", text: $subject, prompt: Text("Email subject"))
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Body") {
                    Picker("Format", selection: $bodyTab) {
                        ForEach(bodyTabs, id: \.self) { tab in
                            Text(tab).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    if bodyTab == "Text" {
                        TextEditor(text: $textBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                    } else {
                        TextEditor(text: $htmlBody)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if sent {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("Send") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSending)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .onAppear {
            if let prefilledFrom {
                from = prefilledFrom
            }
        }
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let trimFrom = from.trimmingCharacters(in: .whitespaces)
        let trimTo = to.trimmingCharacters(in: .whitespaces)
        let trimSubject = subject.trimmingCharacters(in: .whitespaces)
        let hasBody = !textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !trimFrom.isEmpty && !trimTo.isEmpty && !trimSubject.isEmpty && hasBody
    }

    private func parseAddresses(_ input: String) -> [String] {
        input.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func send() {
        isSending = true
        serviceError = nil
        Task {
            do {
                let toAddrs = parseAddresses(to)
                let ccAddrs = parseAddresses(cc)
                let text = textBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : textBody
                let html = htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : htmlBody
                _ = try await service.sendEmail(
                    source: from.trimmingCharacters(in: .whitespaces),
                    toAddresses: toAddrs,
                    ccAddresses: ccAddrs,
                    subject: subject.trimmingCharacters(in: .whitespaces),
                    textBody: text,
                    htmlBody: html
                )
                sent = true
                try? await Task.sleep(for: .seconds(0.6))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSending = false
            }
        }
    }
}
