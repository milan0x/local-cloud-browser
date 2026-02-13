import SwiftUI
import AppKit

struct SQSMessageBrowserView: View {
    @ObservedObject var service: SQSService
    let queue: SQSQueue
    @ObservedObject var toolbarState: SQSToolbarState
    @ObservedObject var favoriteStore: SQSFavoriteStore
    @EnvironmentObject private var appState: AppState

    @State private var messages: [SQSMessage] = []
    @State private var selectedMessageIDs: Set<SQSMessage.ID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serviceError: ServiceError?
    @State private var searchQuery = ""
    @State private var showSendSheet = false
    @State private var editingFavorite: SavedSQSFavorite?
    @State private var messageToView: SQSMessage?
    @State private var messagesToDelete: [SQSMessage] = []
    @State private var showAttributesSheet = false
    @State private var lastLoadTime: Date?
    @State private var sortOrder = [KeyPathComparator(\SQSMessage.sentTimestampMillis, order: .reverse)]
    @SceneStorage("SQSMessageColumns") private var columnCustomization: TableColumnCustomization<SQSMessage>

    // Favorites
    @State private var armedFavoriteId: UUID?
    @State private var sendingFavoriteId: UUID?

    private var queueFavorites: [SavedSQSFavorite] {
        favoriteStore.favorites(for: queue.queueUrl)
    }

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
            if !queueFavorites.isEmpty {
                Divider()
                favoritesBar
            }
        }
        .sheet(isPresented: $showSendSheet) {
            SQSSendMessageView(
                service: service,
                queue: queue,
                favoriteStore: favoriteStore,
                editingFavorite: editingFavorite
            )
            .onDisappear {
                editingFavorite = nil
                receiveMessages(force: true)
            }
        }
        .sheet(item: $messageToView) { message in
            SQSMessageDetailView(message: message, queueName: queue.queueName)
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
            armedFavoriteId = nil
            sendingFavoriteId = nil
            receiveMessages()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showSendSheet && messagesToDelete.isEmpty && messageToView == nil && !showAttributesSheet && !isLoading else { return }
            receiveMessages(force: true, silent: true)
        }
        .onChange(of: selectedMessageIDs) {
            toolbarState.hasSelection = !selectedMessageIDs.isEmpty
            armedFavoriteId = nil
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
            Table(sortedMessages, selection: $selectedMessageIDs, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
                TableColumn("Message ID", value: \.messageId) { msg in
                    Text(msg.truncatedId)
                        .font(.system(.body, design: .monospaced))
                        .help(msg.messageId)
                }
                .width(min: 100, ideal: 115)
                .customizationID("messageId")

                TableColumn("Body") { msg in
                    Text(msg.body.prefix(100).replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                        .help(msg.body.prefix(500))
                }
                .width(min: 150)
                .customizationID("body")

                TableColumn("Type", value: \.bodyType) { msg in
                    Text(msg.bodyType)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 36)
                        .padding(.vertical, 1)
                        .background(bodyTypeBadgeColor(msg.bodyType), in: Capsule())
                        .foregroundStyle(bodyTypeForegroundColor(msg.bodyType))
                }
                .width(min: 40, ideal: 45)
                .customizationID("type")

                TableColumn("Sent", value: \.sentTimestampMillis) { msg in
                    if let date = msg.sentTimestamp {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .width(min: 60, ideal: 75)
                .customizationID("sent")

                TableColumn("Size", value: \.bodySize) { msg in
                    Text(SQSMessage.formattedSize(msg.bodySize))
                        .foregroundStyle(.secondary)
                }
                .width(min: 40, ideal: 50)
                .customizationID("size")

                TableColumn("Receives", value: \.approximateReceiveCount) { msg in
                    Text("\(msg.approximateReceiveCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 45, ideal: 55)
                .customizationID("receives")
                .defaultVisibility(.hidden)

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
                .customizationID("groupId")
                .defaultVisibility(.hidden)

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
                .customizationID("firstReceived")
                .defaultVisibility(.hidden)
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
            if selectedMessageIDs.count > 1 {
                Text("(\(selectedMessageIDs.count) selected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Favorites Bar

    private var favoritesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(queueFavorites) { fav in
                    FavoriteChip(
                        favorite: fav,
                        isArmed: armedFavoriteId == fav.id,
                        isSending: sendingFavoriteId == fav.id,
                        isReadOnly: appState.isReadOnly
                    ) {
                        chipTapped(fav)
                    }
                    .contextMenu {
                        Button("Send") { sendFavorite(fav) }
                            .disabled(appState.isReadOnly)
                        Button("Edit") {
                            editingFavorite = fav
                            showSendSheet = true
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            favoriteStore.delete(id: fav.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 36)
        .background(.bar)
    }

    // MARK: - Favorite Actions

    private func chipTapped(_ favorite: SavedSQSFavorite) {
        guard !appState.isReadOnly else { return }
        if armedFavoriteId == favorite.id {
            sendFavorite(favorite)
        } else {
            armedFavoriteId = favorite.id
        }
    }

    private func sendFavorite(_ favorite: SavedSQSFavorite) {
        guard !appState.isReadOnly else { return }
        armedFavoriteId = nil
        sendingFavoriteId = favorite.id
        Task {
            do {
                _ = try await service.sendMessage(
                    queueUrl: queue.queueUrl,
                    body: favorite.messageBody,
                    delaySeconds: favorite.delaySeconds,
                    messageGroupId: favorite.messageGroupId,
                    messageDeduplicationId: favorite.messageDeduplicationId
                )
                receiveMessages(force: true)
            } catch {
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            sendingFavoriteId = nil
        }
    }

    // MARK: - Data

    private func receiveMessages(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
            toolbarState.isLoading = true
        }
        Task {
            do {
                let received = try await service.receiveMessages(queueUrl: queue.queueUrl)
                // Deduplicate by messageId, keeping latest receipt handle
                var byId: [String: SQSMessage] = [:]
                for msg in messages { byId[msg.messageId] = msg }
                for msg in received { byId[msg.messageId] = msg }
                // Only update the array if the set of message IDs changed
                // (receiptHandle changes every receive, so full equality always fails)
                let freshIDs = Set(byId.keys)
                let currentIDs = Set(messages.map(\.messageId))
                if freshIDs != currentIDs {
                    messages = Array(byId.values)
                }
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                toolbarState.isLoading = false
                lastLoadTime = Date()
            }
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

// MARK: - FavoriteChip

private struct FavoriteChip: View {
    let favorite: SavedSQSFavorite
    let isArmed: Bool
    let isSending: Bool
    let isReadOnly: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if isSending {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                }
                Text(isArmed ? "Click to Send" : favorite.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isArmed ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isArmed ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isReadOnly ? Color.secondary : isArmed ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .help(favorite.messageBody.prefix(200).description)
    }
}
