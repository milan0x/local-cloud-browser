import SwiftUI

struct SQSMessageDetailView: View {
    let message: SQSMessage
    let queueName: String
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Details") {
                    LabeledContent("Queue") {
                        CopyableValue(text: queueName)
                    }
                    LabeledContent("Message ID") {
                        CopyableValue(text: message.messageId, monospaced: true, allowsWrapping: true)
                    }
                    LabeledContent("Type") {
                        Text(message.bodyType)
                    }
                    if let date = message.sentTimestamp {
                        LabeledContent("Sent") {
                            CopyableValue(text: Self.dateFormatter.string(from: date))
                        }
                    }
                    LabeledContent("Size") {
                        Text(SQSMessage.formattedSize(message.bodySize))
                    }
                    if let groupId = message.messageGroupId {
                        LabeledContent("Group ID") {
                            CopyableValue(text: groupId, monospaced: true, allowsWrapping: true)
                        }
                    }
                    if let date = message.firstReceiveTimestamp {
                        LabeledContent("First Received") {
                            CopyableValue(text: Self.dateFormatter.string(from: date))
                        }
                    }
                    LabeledContent("Receive Count") {
                        CopyableValue(text: "\(message.approximateReceiveCount)")
                    }
                    LabeledContent("MD5") {
                        CopyableValue(text: message.md5OfBody, monospaced: true, allowsWrapping: true)
                    }
                }

                Section {
                    ScrollView {
                        Text(formattedBody)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 300)
                } header: {
                    HStack {
                        Text("Body")
                        Spacer()
                        CopyButton(text: message.body)
                    }
                }

                if !message.attributes.isEmpty {
                    Section("Attributes") {
                        ForEach(message.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key) {
                                CopyableValue(text: value, monospaced: true, allowsWrapping: true)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 450)
    }

    private var formattedBody: String {
        // Try to pretty-print JSON
        guard let data = message.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let formatted = String(data: pretty, encoding: .utf8) else {
            return message.body
        }
        return formatted
    }
}
