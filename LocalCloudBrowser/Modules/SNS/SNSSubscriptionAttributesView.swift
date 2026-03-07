import SwiftUI

struct SNSSubscriptionAttributesView: View {
    @ObservedObject var service: SNSService
    let subscription: SNSSubscription
    @Environment(\.dismiss) private var dismiss

    @State private var attributes: SNSSubscriptionAttributes?
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
        .frame(minHeight: 350)
        .task { loadAttributes() }
    }

    @ViewBuilder
    private func attributesForm(_ attrs: SNSSubscriptionAttributes) -> some View {
        Form {
            Section("Subscription Info") {
                LabeledContent("Protocol") {
                    Text(attrs.protocol_)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Endpoint") {
                    CopyableValue(text: attrs.endpoint, monospaced: true, allowsWrapping: true)
                }
                LabeledContent("Subscription ARN") {
                    CopyableValue(text: attrs.subscriptionArn, monospaced: true, allowsWrapping: true)
                }
                LabeledContent("Topic ARN") {
                    CopyableValue(text: attrs.topicArn, monospaced: true, allowsWrapping: true)
                }
                if !attrs.owner.isEmpty {
                    LabeledContent("Owner") {
                        Text(attrs.owner)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Section("Status") {
                LabeledContent("Confirmed") {
                    Text(attrs.pendingConfirmation ? "No" : "Yes")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Authenticated") {
                    Text(attrs.confirmationWasAuthenticated ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Raw Message Delivery") {
                    Text(attrs.rawMessageDelivery ? "Enabled" : "Disabled")
                        .foregroundStyle(.secondary)
                }
            }

            if let filterPolicy = attrs.filterPolicy, !filterPolicy.isEmpty {
                Section {
                    Text(prettyJSON(filterPolicy))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let scope = attrs.filterPolicyScope, !scope.isEmpty {
                        LabeledContent("Scope") {
                            Text(scope)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Filter Policy")
                        Spacer()
                        CopyButton(text: filterPolicy)
                    }
                }
            }

            if let redrivePolicy = attrs.redrivePolicy, !redrivePolicy.isEmpty {
                Section {
                    Text(prettyJSON(redrivePolicy))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("Redrive Policy")
                        Spacer()
                        CopyButton(text: redrivePolicy)
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
                let dict = try await service.getSubscriptionAttributes(subscriptionArn: subscription.subscriptionArn)
                attributes = SNSSubscriptionAttributes(from: dict)
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
