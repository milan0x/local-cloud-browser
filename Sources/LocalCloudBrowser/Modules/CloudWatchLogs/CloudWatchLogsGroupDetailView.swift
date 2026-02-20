import SwiftUI

struct CloudWatchLogsGroupDetailView: View {
    let logGroup: CloudWatchLogGroup
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
                Section("Log Group Info") {
                    LabeledContent("Name") {
                        CopyableValue(text: logGroup.logGroupName)
                    }
                    if let arn = logGroup.arn {
                        LabeledContent("ARN") {
                            CopyableValue(text: arn, monospaced: true, allowsWrapping: true)
                        }
                    }
                    LabeledContent("Retention") {
                        if let days = logGroup.retentionInDays {
                            Text("\(days) days")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never expire")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Stored Bytes") {
                        Text(logGroup.formattedStoredBytes)
                            .foregroundStyle(.secondary)
                    }
                }

                if let created = logGroup.creationTime {
                    Section("Dates") {
                        LabeledContent("Created") {
                            CopyableValue(text: Self.dateFormatter.string(from: created))
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
