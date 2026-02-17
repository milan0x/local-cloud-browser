import SwiftUI
import AppKit

struct SQSQueueListView: View {
    @ObservedObject var service: SQSService
    @EnvironmentObject private var appState: AppState
    @Binding var selectedQueueIDs: Set<SQSQueue.ID>
    @Binding var activeQueue: SQSQueue?
    var restoreQueueName: String?

    @StateObject private var loader = ListLoader<SQSQueue>()
    private var queues: [SQSQueue] { loader.items }
    @State private var messageCounts: [String: Int] = [:]  // queueUrl -> count
    @State private var showCreateSheet = false
    @State private var queuesToDelete: [SQSQueue] = []
    @State private var queueToPurge: SQSQueue?
    @State private var serviceError: ServiceError?
    @State private var queueToShowAttributes: SQSQueue?

    var body: some View {
        VStack(spacing: 0) {
            queueListHeader
            Divider()
            queueListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SQSCreateQueueView(service: service, existingQueueNames: Set(queues.map(\.queueName)))
                .onDisappear { loadQueues(force: true) }
        }
        .deleteConfirmation(items: $queuesToDelete, noun: "Queue") { items in
            if items.count == 1, let queue = items.first {
                Text("Are you sure you want to delete \"\(queue.queueName)\"?\n\nThis cannot be undone.")
            } else {
                let names = items.map(\.queueName).joined(separator: "\n")
                Text("Are you sure you want to delete these queues?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteQueues($0) }
        .alert(
            "Purge Queue",
            isPresented: Binding(
                get: { queueToPurge != nil },
                set: { if !$0 { queueToPurge = nil } }
            )
        ) {
            Button("Purge", role: .destructive) {
                if let queue = queueToPurge {
                    purgeQueue(queue)
                }
                queueToPurge = nil
            }
            Button("Cancel", role: .cancel) {
                queueToPurge = nil
            }
        } message: {
            if let queue = queueToPurge {
                Text("This will permanently delete ALL messages in \"\(queue.queueName)\".\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $queueToShowAttributes) { queue in
            SQSQueueAttributesView(service: service, queue: queue)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadQueues() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && queuesToDelete.isEmpty && queueToPurge == nil && queueToShowAttributes == nil && !loader.isLoading }) {
            loadQueues(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedQueueIDs = []
            activeQueue = nil
            loader.items = []
            messageCounts = [:]
            loadQueues(force: true)
        }
        .syncSelection(selectedQueueIDs, items: queues, activeItem: $activeQueue)
    }

    private var queueDeleteDisabled: Bool {
        appState.isReadOnly || selectedQueueIDs.isEmpty
    }

    // MARK: - Header

    private var queueListHeader: some View {
        ListHeaderBar(
            title: "Queues",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: queueDeleteDisabled,
            deleteHelp: selectedQueueIDs.count <= 1 ? "Delete Queue" : "Delete \(selectedQueueIDs.count) Queues",
            onRefresh: { loadQueues(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { queuesToDelete = queues.filter { selectedQueueIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var queueListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: queues.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading queues...", onRetry: { loadQueues(force: true) }) {
            List(selection: $selectedQueueIDs) {
                if queues.isEmpty {
                    EmptyStateView(icon: "tray.2", message: "No queues")
                        .listRowSeparator(.hidden)
                }

                ForEach(queues) { queue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(queue.queueName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            StatusBadge(text: queue.isFifo ? "FIFO" : "Standard", color: queue.isFifo ? .blue : .gray)
                            if let count = messageCounts[queue.queueUrl] {
                                Text("~\(count) msgs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(selectedQueueIDs.contains(queue.id) ? Color.white : Color.primary)
                    .tag(queue.id)
                    .contextMenu {
                        Button("View Attributes") {
                            queueToShowAttributes = queue
                        }
                        Divider()
                        Button("Copy Queue URL") { copyToClipboard(queue.queueUrl) }
                        Button("Copy Queue ARN") {
                            if let arn = queue.queueArn(region: appState.region) {
                                copyToClipboard(arn)
                            }
                        }
                        Button("Copy Queue Name") { copyToClipboard(queue.queueName) }
                        Menu("Copy as AWS CLI") {
                            Button("Send Message") {
                                copyToClipboard(queue.sendMessageCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Receive Message") {
                                copyToClipboard(queue.receiveMessageCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Get Attributes") {
                                copyToClipboard(queue.getAttributesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Queue") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Purge Queue") {
                            queueToPurge = queue
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedQueueIDs.count > 1 && selectedQueueIDs.contains(queue.id) {
                            let selected = queues.filter { selectedQueueIDs.contains($0.id) }
                            Button("Delete \(selected.count) Queues", role: .destructive) {
                                queuesToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                queuesToDelete = [queue]
                            }
                            .disabled(appState.isReadOnly)
                        }
                    }
                }

            }
            .overlay(alignment: .bottom) {
                if loader.errorMessage != nil {
                    ConnectionLostBanner()
                }
            }
            .contextMenu {
                Button("Create Queue") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
            .background(DoubleClickDetector {
                if selectedQueueIDs.count == 1,
                   let id = selectedQueueIDs.first,
                   let queue = queues.first(where: { $0.id == id }) {
                    queueToShowAttributes = queue
                }
            })
        }
    }

    // MARK: - Data

    private func loadQueues(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listQueues() },
            sort: { $0.queueName.localizedStandardCompare($1.queueName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreQueueName,
               let queue = items.first(where: { $0.queueName == savedName }) {
                selectedQueueIDs = [queue.id]
                activeQueue = queue
            }
            loader.hasRestoredSession = true
            await fetchMessageCounts()
        }
    }

    private func fetchMessageCounts() async {
        for queue in queues {
            do {
                let attrs = try await service.getQueueAttributes(
                    queueUrl: queue.queueUrl,
                    attributeNames: ["ApproximateNumberOfMessages"]
                )
                messageCounts[queue.queueUrl] = Int(attrs["ApproximateNumberOfMessages"] ?? "") ?? 0
            } catch {
                Log.warn("Failed to fetch message count for \(queue.queueName): \(error.localizedDescription)", category: "SQS")
            }
        }
    }

    private func deleteQueues(_ targets: [SQSQueue]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteQueue(queueUrl: $0.queueUrl)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedQueueIDs.subtract(deleted)
                if let active = activeQueue, deleted.contains(active.id) { activeQueue = nil }
                loadQueues(force: true)
            }
        }
    }

    private func purgeQueue(_ queue: SQSQueue) {
        Task {
            do {
                try await service.purgeQueue(queueUrl: queue.queueUrl)
                loadQueues(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
