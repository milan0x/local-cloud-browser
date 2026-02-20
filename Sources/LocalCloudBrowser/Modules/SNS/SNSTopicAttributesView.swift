import SwiftUI

struct SNSTopicAttributesView: View {
    @ObservedObject var service: SNSService
    let topic: SNSTopic
    @Environment(\.dismiss) private var dismiss

    @State private var attributes: SNSTopicAttributes?
    @State private var isLoadingAttributes = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoadingAttributes {
                ProgressView("Loading attributes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadAttributes() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let attrs = attributes {
                attributesForm(attrs)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 400)
        .task { loadAttributes() }
    }

    @ViewBuilder
    private func attributesForm(_ attrs: SNSTopicAttributes) -> some View {
        Form {
            Section("Topic Info") {
                LabeledContent("Name") {
                    CopyableValue(text: topic.topicName)
                }
                LabeledContent("ARN") {
                    CopyableValue(text: attrs.topicArn, monospaced: true, allowsWrapping: true)
                }
                if !attrs.owner.isEmpty {
                    LabeledContent("Owner") {
                        Text(attrs.owner)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                if !attrs.displayName.isEmpty {
                    LabeledContent("Display Name") {
                        CopyableValue(text: attrs.displayName)
                    }
                }
            }

            Section("Subscriptions") {
                LabeledContent("Confirmed") {
                    Text("\(attrs.subscriptionsConfirmed)")
                }
                LabeledContent("Pending") {
                    Text("\(attrs.subscriptionsPending)")
                }
                LabeledContent("Deleted") {
                    Text("\(attrs.subscriptionsDeleted)")
                }
            }

            Section("Configuration") {
                LabeledContent("Type") {
                    Text(attrs.fifoTopic ? "FIFO" : "Standard")
                        .foregroundStyle(.secondary)
                }
                if attrs.fifoTopic {
                    LabeledContent("Content-Based Dedup") {
                        Text(attrs.contentBasedDeduplication ? "Enabled" : "Disabled")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let policy = attrs.policy, !policy.isEmpty {
                Section {
                    Text(prettyJSON(policy))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("Policy")
                        Spacer()
                        CopyButton(text: policy)
                    }
                }
            }

            if let delivery = attrs.effectiveDeliveryPolicy, !delivery.isEmpty {
                Section {
                    Text(prettyJSON(delivery))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("Delivery Policy")
                        Spacer()
                        CopyButton(text: delivery)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func loadAttributes() {
        isLoadingAttributes = true
        loadError = nil
        Task {
            do {
                let dict = try await service.getTopicAttributes(topicArn: topic.topicArn)
                attributes = SNSTopicAttributes(from: dict)
            } catch {
                loadError = error.localizedDescription
            }
            isLoadingAttributes = false
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return str
    }
}
