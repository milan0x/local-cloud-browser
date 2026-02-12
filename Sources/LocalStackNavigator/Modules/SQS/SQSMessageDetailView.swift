import SwiftUI
import AppKit

struct SQSMessageDetailView: View {
    let message: SQSMessage
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
                    LabeledContent("Message ID") {
                        Text(message.messageId)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    LabeledContent("MD5") {
                        Text(message.md5OfBody)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if let date = message.sentTimestamp {
                        LabeledContent("Sent") {
                            Text(Self.dateFormatter.string(from: date))
                        }
                    }
                    LabeledContent("Receive Count") {
                        Text("\(message.approximateReceiveCount)")
                    }
                }

                Section("Body") {
                    ScrollView {
                        Text(formattedBody)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 300)
                }

                if !message.attributes.isEmpty {
                    Section("Attributes") {
                        ForEach(message.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key) {
                                Text(value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Copy Body") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.body, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550)
        .frame(minHeight: 400)
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
