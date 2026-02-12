import SwiftUI

struct SQSQueueAttributesView: View {
    @ObservedObject var service: SQSService
    let queue: SQSQueue
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    // Loaded attributes
    @State private var attributes: SQSQueueAttributes?
    @State private var isLoadingAttributes = false
    @State private var loadError: String?

    // Editable fields
    @State private var visibilityTimeout = ""
    @State private var delaySeconds = ""
    @State private var maximumMessageSize = ""
    @State private var messageRetentionPeriod = ""
    @State private var receiveMessageWaitTimeSeconds = ""
    @State private var contentBasedDeduplication = false

    // DLQ
    @State private var dlqEnabled = false
    @State private var dlqTargetQueueUrl = ""
    @State private var dlqMaxReceiveCount = "5"
    @State private var availableQueues: [SQSQueue] = []

    // Save state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isDirty = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

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
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer()
                if isDirty && !appState.isReadOnly {
                    Button("Save") { saveAttributes() }
                        .disabled(isSaving || !isValid)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 500)
        .task { loadAttributes() }
    }

    @ViewBuilder
    private func attributesForm(_ attrs: SQSQueueAttributes) -> some View {
        Form {
            Section("Queue Info") {
                LabeledContent("ARN") {
                    CopyableValue(text: attrs.queueArn, monospaced: true, allowsWrapping: true)
                }
                if let created = attrs.createdTimestamp {
                    LabeledContent("Created") {
                        CopyableValue(text: Self.dateFormatter.string(from: created))
                    }
                }
                if let modified = attrs.lastModifiedTimestamp {
                    LabeledContent("Last Modified") {
                        CopyableValue(text: Self.dateFormatter.string(from: modified))
                    }
                }
            }

            Section("Message Counts") {
                LabeledContent("Available") {
                    Text("\(attrs.approximateNumberOfMessages)")
                }
                LabeledContent("In Flight") {
                    Text("\(attrs.approximateNumberOfMessagesNotVisible)")
                }
                LabeledContent("Delayed") {
                    Text("\(attrs.approximateNumberOfMessagesDelayed)")
                }
            }

            Section("Configuration") {
                LabeledContent("Visibility Timeout") {
                    HStack(spacing: 4) {
                        TextField("", text: $visibilityTimeout)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: visibilityTimeout) { isDirty = true }
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                if !isValidRange(visibilityTimeout, 0...43200) {
                    Text("Must be 0–43,200 seconds (0–12 hours)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledContent("Delay") {
                    HStack(spacing: 4) {
                        TextField("", text: $delaySeconds)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: delaySeconds) { isDirty = true }
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                if !isValidRange(delaySeconds, 0...900) {
                    Text("Must be 0–900 seconds (0–15 minutes)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledContent("Max Message Size") {
                    HStack(spacing: 4) {
                        TextField("", text: $maximumMessageSize)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: maximumMessageSize) { isDirty = true }
                        Text("bytes")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                if !isValidRange(maximumMessageSize, 1024...262144) {
                    Text("Must be 1,024–262,144 bytes (1 KB–256 KB)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledContent("Retention Period") {
                    HStack(spacing: 4) {
                        TextField("", text: $messageRetentionPeriod)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: messageRetentionPeriod) { isDirty = true }
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                if !isValidRange(messageRetentionPeriod, 60...1209600) {
                    Text("Must be 60–1,209,600 seconds (1 min–14 days)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                LabeledContent("Receive Wait Time") {
                    HStack(spacing: 4) {
                        TextField("", text: $receiveMessageWaitTimeSeconds)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: receiveMessageWaitTimeSeconds) { isDirty = true }
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                if !isValidRange(receiveMessageWaitTimeSeconds, 0...20) {
                    Text("Must be 0–20 seconds")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Dead-Letter Queue") {
                Toggle("Enable DLQ", isOn: $dlqEnabled)
                    .disabled(appState.isReadOnly)
                    .onChange(of: dlqEnabled) { isDirty = true }

                if dlqEnabled {
                    let eligibleQueues = availableQueues.filter {
                        $0.queueUrl != queue.queueUrl && $0.isFifo == queue.isFifo
                    }
                    Picker("Target Queue", selection: $dlqTargetQueueUrl) {
                        Text("Select a queue").tag("")
                        ForEach(eligibleQueues) { q in
                            Text(q.queueName).tag(q.queueUrl)
                        }
                    }
                    .disabled(appState.isReadOnly)
                    .onChange(of: dlqTargetQueueUrl) { isDirty = true }

                    LabeledContent("Max Receive Count") {
                        TextField("1-1000", text: $dlqMaxReceiveCount)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .disabled(appState.isReadOnly)
                            .onChange(of: dlqMaxReceiveCount) { isDirty = true }
                    }
                    if !isValidRange(dlqMaxReceiveCount, 1...1000) {
                        Text("Must be 1–1000")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            if queue.isFifo {
                Section("FIFO Settings") {
                    LabeledContent("FIFO Queue") {
                        Text("Yes")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Content-Based Deduplication", isOn: $contentBasedDeduplication)
                        .disabled(appState.isReadOnly)
                        .onChange(of: contentBasedDeduplication) { isDirty = true }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Validation

    private func isValidRange(_ text: String, _ range: ClosedRange<Int>) -> Bool {
        guard !text.isEmpty, let value = Int(text) else { return text.isEmpty }
        return range.contains(value)
    }

    private var isValid: Bool {
        isValidRange(visibilityTimeout, 0...43200)
            && isValidRange(delaySeconds, 0...900)
            && isValidRange(maximumMessageSize, 1024...262144)
            && isValidRange(messageRetentionPeriod, 60...1209600)
            && isValidRange(receiveMessageWaitTimeSeconds, 0...20)
            && (!dlqEnabled || (!dlqTargetQueueUrl.isEmpty && isValidRange(dlqMaxReceiveCount, 1...1000)))
    }

    // MARK: - Data

    private func loadAttributes() {
        isLoadingAttributes = true
        loadError = nil
        Task {
            do {
                let dict = try await service.getQueueAttributes(queueUrl: queue.queueUrl)
                let attrs = SQSQueueAttributes(from: dict)
                attributes = attrs
                populateFields(from: attrs)

                // Load available queues for DLQ picker
                availableQueues = (try? await service.listQueues()) ?? []
            } catch {
                loadError = error.localizedDescription
            }
            isLoadingAttributes = false
        }
    }

    private func populateFields(from attrs: SQSQueueAttributes) {
        visibilityTimeout = "\(attrs.visibilityTimeout)"
        delaySeconds = "\(attrs.delaySeconds)"
        maximumMessageSize = "\(attrs.maximumMessageSize)"
        messageRetentionPeriod = "\(attrs.messageRetentionPeriod)"
        receiveMessageWaitTimeSeconds = "\(attrs.receiveMessageWaitTimeSeconds)"
        contentBasedDeduplication = attrs.contentBasedDeduplication

        if let redrive = attrs.redrivePolicy {
            dlqEnabled = true
            // Find queue URL from ARN
            let arnQueueName = redrive.deadLetterTargetArn.components(separatedBy: ":").last ?? ""
            dlqTargetQueueUrl = availableQueues.first { $0.queueName == arnQueueName }?.queueUrl ?? ""
            dlqMaxReceiveCount = "\(redrive.maxReceiveCount)"
        } else {
            dlqEnabled = false
            dlqTargetQueueUrl = ""
            dlqMaxReceiveCount = "5"
        }

        isDirty = false
    }

    private func saveAttributes() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                var newAttrs: [String: String] = [:]
                if !visibilityTimeout.isEmpty { newAttrs["VisibilityTimeout"] = visibilityTimeout }
                if !delaySeconds.isEmpty { newAttrs["DelaySeconds"] = delaySeconds }
                if !maximumMessageSize.isEmpty { newAttrs["MaximumMessageSize"] = maximumMessageSize }
                if !messageRetentionPeriod.isEmpty { newAttrs["MessageRetentionPeriod"] = messageRetentionPeriod }
                if !receiveMessageWaitTimeSeconds.isEmpty { newAttrs["ReceiveMessageWaitTimeSeconds"] = receiveMessageWaitTimeSeconds }

                if queue.isFifo {
                    newAttrs["ContentBasedDeduplication"] = contentBasedDeduplication ? "true" : "false"
                }

                if dlqEnabled, !dlqTargetQueueUrl.isEmpty {
                    // Build ARN from queue URL
                    let targetQueue = availableQueues.first { $0.queueUrl == dlqTargetQueueUrl }
                    let targetName = targetQueue?.queueName ?? ""
                    let region = appState.region
                    let arn = "arn:aws:sqs:\(region):000000000000:\(targetName)"
                    let maxReceive = Int(dlqMaxReceiveCount) ?? 5
                    let redrive = SQSRedrivePolicy(deadLetterTargetArn: arn, maxReceiveCount: maxReceive)
                    newAttrs["RedrivePolicy"] = redrive.toJSON()
                } else if !dlqEnabled {
                    // Remove redrive policy by setting empty string
                    if attributes?.redrivePolicy != nil {
                        newAttrs["RedrivePolicy"] = ""
                    }
                }

                try await service.setQueueAttributes(queueUrl: queue.queueUrl, attributes: newAttrs)

                // Reload to confirm
                let dict = try await service.getQueueAttributes(queueUrl: queue.queueUrl)
                let attrs = SQSQueueAttributes(from: dict)
                attributes = attrs
                populateFields(from: attrs)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
