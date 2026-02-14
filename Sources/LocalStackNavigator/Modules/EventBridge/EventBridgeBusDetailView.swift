import SwiftUI

struct EventBridgeBusDetailView: View {
    let bus: EventBridgeBus
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
                Section("Event Bus Info") {
                    LabeledContent("Name") {
                        CopyableValue(text: bus.name)
                    }
                    if let arn = bus.arn {
                        LabeledContent("ARN") {
                            CopyableValue(text: arn, monospaced: true, allowsWrapping: true)
                        }
                    }
                    if let desc = bus.description, !desc.isEmpty {
                        LabeledContent("Description") {
                            Text(desc)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Default") {
                        Text(bus.isDefault ? "Yes" : "No")
                            .foregroundStyle(.secondary)
                    }
                }

                if bus.creationTime != nil || bus.lastModifiedTime != nil {
                    Section("Dates") {
                        if let created = bus.creationTime {
                            LabeledContent("Created") {
                                CopyableValue(text: Self.dateFormatter.string(from: created))
                            }
                        }
                        if let modified = bus.lastModifiedTime {
                            LabeledContent("Last Modified") {
                                CopyableValue(text: Self.dateFormatter.string(from: modified))
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
        .frame(minHeight: 300)
    }
}
