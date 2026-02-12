import SwiftUI
import AppKit

struct SQSMessageBrowserView: View {
    @ObservedObject var service: SQSService
    let queue: SQSQueue
    @ObservedObject var toolbarState: SQSToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var autoRefresh: AutoRefreshManager

    @State private var messages: [SQSMessage] = []
    @State private var selectedMessageIDs: Set<SQSMessage.ID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serviceError: ServiceError?
    @State private var searchQuery = ""
    @State private var showSendSheet = false
    @State private var messageToView: SQSMessage?
    @State private var messagesToDelete: [SQSMessage] = []
    @State private var showAttributesSheet = false
    @State private var lastLoadTime: Date?
    @State private var sortOrder = [KeyPathComparator(\SQSMessage.sentTimestampMillis, order: .reverse)]

    private var sortedMessages: [SQSMessage] {
        let filtered: [SQSMessage]
        if searchQuery.isEmpty {
            filtered = messages
        } else {
            let query = searchQuery.lowercased()
            filtered = messages.filter {
                $0.messageId.lowercased().contains(query)
                    || $0.body.lowercased().contains(query)
            }
        }
        return filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageHeader
            Divider()
            messageContent
            Divider()
            messageStatusBar
        }
        .sheet(isPresented: $showSendSheet) {
            SQSSendMessageView(service: service, queue: queue)
                .onDisappear { receiveMessages(force: true) }
        }
        .sheet(item: $messageToView) { message in
            SQSMessageDetailView(message: message)
        }
        .sheet(isPresented: $showAttributesSheet) {
            SQSQueueAttributesView(service: service, queue: queue)
        }
        .alert(
            messagesToDelete.count == 1
                ? "Delete Message"
                : "Delete \(messagesToDelete.count) Messages",
            isPresented: Binding(
                get: { !messagesToDelete.isEmpty },
                set: { if !$0 { messagesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteMessages(messagesToDelete)
            }
            Button("Cancel", role: .cancel) {
                messagesToDelete = []
            }
        } message: {
            if messagesToDelete.count == 1, let msg = messagesToDelete.first {
                Text("Delete message \(msg.messageId.prefix(8))...?\n\nThis cannot be undone.")
            } else {
                Text("Delete \(messagesToDelete.count) messages?\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task(id: queue.id) {
            messages = []
            selectedMessageIDs = []
            lastLoadTime = nil
            receiveMessages()
        }
        .onChange(of: autoRefresh.refreshTrigger) {
            guard !showSendSheet && messagesToDelete.isEmpty && messageToView == nil && !showAttributesSheet && !isLoading else { return }
            receiveMessages(force: true)
        }
        .onChange(of: selectedMessageIDs) {
            toolbarState.hasSelection = !selectedMessageIDs.isEmpty
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            toolbarState.pendingAction = nil
            switch action {
            case .sendMessage:
                showSendSheet = true
            case .receiveMessages:
                receiveMessages(force: true)
            case .deleteSelected:
                let selected = messages.filter { selectedMessageIDs.contains($0.id) }
                if !selected.isEmpty { messagesToDelete = selected }
            case .showAttributes:
                showAttributesSheet = true
            default:
                break
            }
        }
    }

    // MARK: - Header

    private var messageHeader: some View {
        HStack {
            Text(queue.queueName)
                .font(.headline)
                .lineLimit(1)

            Text(queue.isFifo ? "FIFO" : "Standard")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(queue.isFifo ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(queue.isFifo ? .blue : .secondary)

            Spacer()

            SearchBarView(query: $searchQuery, placeholder: "Search messages")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var messageContent: some View {
        if isLoading && messages.isEmpty {
            ProgressView("Receiving messages...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { receiveMessages(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if messages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No messages")
                    .foregroundStyle(.secondary)
                Text("Send a message or click Receive to poll the queue.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedMessages, selection: $selectedMessageIDs, sortOrder: $sortOrder) {
                TableColumn("Message ID", value: \.messageId) { msg in
                    Text(msg.truncatedId)
                        .font(.system(.body, design: .monospaced))
                        .help(msg.messageId)
                }
                .width(min: 130, ideal: 160)

                TableColumn("Type", value: \.bodyType) { msg in
                    Text(msg.bodyType)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(bodyTypeBadgeColor(msg.bodyType), in: Capsule())
                        .foregroundStyle(bodyTypeForegroundColor(msg.bodyType))
                }
                .width(min: 45, ideal: 55)

                TableColumn("Body") { msg in
                    Text(msg.body.prefix(100).replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                        .help(msg.body.prefix(500))
                }
                .width(min: 150)

                TableColumn("Size", value: \.bodySize) { msg in
                    Text(SQSMessage.formattedSize(msg.bodySize))
                        .foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 65)

                TableColumn("Sent", value: \.sentTimestampMillis) { msg in
                    if let date = msg.sentTimestamp {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 80, ideal: 100)

                TableColumn("Receives", value: \.approximateReceiveCount) { msg in
                    Text("\(msg.approximateReceiveCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 70)

                TableColumn("Group ID") { msg in
                    if let groupId = msg.messageGroupId {
                        Text(groupId)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .help(groupId)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 70, ideal: 90)

                TableColumn("First Received") { msg in
                    if let date = msg.firstReceiveTimestamp {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 80, ideal: 110)
            }
            .contextMenu(forSelectionType: SQSMessage.ID.self) { selection in
                if let id = selection.first, let msg = messages.first(where: { $0.id == id }) {
                    Button("View Details") {
                        messageToView = msg
                    }
                    Divider()
                    Button("Copy Message ID") { copyToClipboard(msg.messageId) }
                    Button("Copy Body") { copyToClipboard(msg.body) }
                    Divider()
                    if selection.count > 1 {
                        let selected = messages.filter { selection.contains($0.id) }
                        Button("Delete \(selected.count) Messages", role: .destructive) {
                            messagesToDelete = selected
                        }
                        .disabled(appState.isReadOnly)
                    } else {
                        Button("Delete", role: .destructive) {
                            messagesToDelete = [msg]
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
            } primaryAction: { selection in
                if let id = selection.first, let msg = messages.first(where: { $0.id == id }) {
                    messageToView = msg
                }
            }
        }
    }

    // MARK: - Status Bar

    private var messageStatusBar: some View {
        HStack {
            Text("\(messages.count) message\(messages.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !searchQuery.isEmpty {
                Text("(\(sortedMessages.count) shown)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private func receiveMessages(force: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        isLoading = true
        errorMessage = nil
        toolbarState.isLoading = true
        Task {
            do {
                let received = try await service.receiveMessages(queueUrl: queue.queueUrl)
                // Deduplicate by messageId, keeping latest
                var byId: [String: SQSMessage] = [:]
                for msg in messages { byId[msg.messageId] = msg }
                for msg in received { byId[msg.messageId] = msg }
                messages = Array(byId.values)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            toolbarState.isLoading = false
            lastLoadTime = Date()
        }
    }

    private func deleteMessages(_ targets: [SQSMessage]) {
        Task {
            var deletedIDs: Set<SQSMessage.ID> = []
            for msg in targets {
                do {
                    try await service.deleteMessage(queueUrl: queue.queueUrl, receiptHandle: msg.receiptHandle)
                    deletedIDs.insert(msg.id)
                } catch {
                    if let clientError = error as? LocalStackClientError,
                       let parsed = clientError.serviceError {
                        serviceError = parsed
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            if !deletedIDs.isEmpty {
                messages.removeAll { deletedIDs.contains($0.id) }
                selectedMessageIDs.subtract(deletedIDs)
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func bodyTypeBadgeColor(_ type: String) -> Color {
        switch type {
        case "JSON": return Color.blue.opacity(0.15)
        case "XML": return Color.orange.opacity(0.15)
        default: return Color.gray.opacity(0.15)
        }
    }

    private func bodyTypeForegroundColor(_ type: String) -> Color {
        switch type {
        case "JSON": return .blue
        case "XML": return .orange
        default: return .secondary
        }
    }
}
