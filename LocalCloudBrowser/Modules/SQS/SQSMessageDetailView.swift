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
        let trimmed = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return message.body
        }
        // Pretty-print at string level to preserve original key order
        // (JSONSerialization round-trip uses NSDictionary which scrambles order)
        return Self.prettyPrintJSON(trimmed)
    }

    /// Indent JSON string without parsing into a dictionary, preserving key order.
    private static func prettyPrintJSON(_ json: String) -> String {
        var result = ""
        var indent = 0
        var inString = false
        var escaped = false
        let tab = "  "

        for char in json {
            if escaped {
                result.append(char)
                escaped = false
                continue
            }
            if char == "\\" && inString {
                result.append(char)
                escaped = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                result.append(char)
                continue
            }
            if inString {
                result.append(char)
                continue
            }
            switch char {
            case "{", "[":
                result.append(char)
                indent += 1
                result.append("\n")
                result.append(String(repeating: tab, count: indent))
            case "}", "]":
                indent = max(0, indent - 1)
                result.append("\n")
                result.append(String(repeating: tab, count: indent))
                result.append(char)
            case ",":
                result.append(char)
                result.append("\n")
                result.append(String(repeating: tab, count: indent))
            case ":":
                result.append(": ")
            case " ", "\n", "\r", "\t":
                break // skip existing whitespace outside strings
            default:
                result.append(char)
            }
        }
        return result
    }
}
