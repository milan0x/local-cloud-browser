import SwiftUI
import AppKit

struct SQSQueueListView: View {
    @ObservedObject var service: SQSService
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedQueueIDs: Set<SQSQueue.ID>
    @Binding var activeQueue: SQSQueue?
    var restoreQueueName: String?
    var searchFocusTrigger: Int = 0
    var paneFocusTrigger: Int = 0

    @FocusState private var isListFocused: Bool
    @StateObject private var loader = ListLoader<SQSQueue>()
    private var queues: [SQSQueue] { loader.items }
    @State private var messageCounts: [String: Int] = [:]  // queueUrl -> count
    @State private var showCreateSheet = false
    @State private var pendingSelectName: String?
    /// Queue names recently deleted locally. SQS DeleteQueue is eventually
    /// consistent: ListQueues can keep returning the deleted queue for up to
    /// 60 seconds. We filter these out of every refetch during that window so
    /// the UI doesn't resurrect them.
    @State private var recentlyDeletedNames: Set<String> = []
    @State private var queuesToDelete: [SQSQueue] = []
    @State private var queueToPurge: SQSQueue?
    @State private var serviceError: ServiceError?
    @State private var queueToShowAttributes: SQSQueue?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            queueListHeader
            Divider()
            queueListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SQSCreateQueueView(service: service, existingQueueNames: Set(queues.map(\.queueName))) { name, url in
                // Optimistic insertion: show the new queue immediately so the user
                // gets instant feedback. SQS is eventually consistent — ListQueues
                // can take seconds to include the new queue — so the background
                // reload below handles the official sync.
                let newQueue = SQSQueue(queueUrl: url)
                if !loader.items.contains(where: { $0.queueName == newQueue.queueName }) {
                    loader.items.append(newQueue)
                    loader.items.sort { $0.queueName.localizedStandardCompare($1.queueName) == .orderedAscending }
                }
                pendingSelectName = name
                selectedQueueIDs = [newQueue.id]
                activeQueue = newQueue
            }
            .onDisappear {
                // SQS eventual consistency: retry a few times so the
                // listing eventually confirms the newly-created queue.
                Task {
                    for attempt in 0..<5 {
                        loadQueues(force: true, silent: attempt > 0)
                        try? await Task.sleep(for: .seconds(1))
                        if pendingSelectName == nil { break }
                    }
                }
            }
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
        .onChange(of: paneFocusTrigger) {
            isListFocused = true
        }
    }

    private var filteredQueues: [SQSQueue] {
        guard !searchText.isEmpty else { return queues }
        let query = searchText.lowercased()
        return queues.filter { $0.queueName.lowercased().contains(query) }
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
            itemCount: queues.count,
            deleteDisabled: queueDeleteDisabled,
            deleteHelp: selectedQueueIDs.count <= 1 ? "Delete Queue" : "Delete \(selectedQueueIDs.count) Queues",
            onRefresh: { loadQueues(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { queuesToDelete = queues.filter { selectedQueueIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var queueListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: queues.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading queues...", emptyIcon: "tray.2", emptyMessage: "No queues", onRetry: { loadQueues(force: true) }) {
            VStack(spacing: 0) {
                if queues.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter queues", focusTrigger: searchFocusTrigger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedQueueIDs) {
                    ForEach(filteredQueues) { queue in
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
                    .selectionForeground()
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
            .focused($isListFocused)
            .background(DoubleClickDetector {
                if selectedQueueIDs.count == 1,
                   let id = selectedQueueIDs.first,
                   let queue = queues.first(where: { $0.id == id }) {
                    queueToShowAttributes = queue
                }
            })
            }
        }
    }

    // MARK: - Data

    private func loadQueues(force: Bool = false, silent: Bool = false) {
        let deletedSnapshot = recentlyDeletedNames
        loader.load(force: force, silent: silent,
            fetch: { [service] in
                let all = try await service.listQueues()
                guard !deletedSnapshot.isEmpty else { return all }
                return all.filter { !deletedSnapshot.contains($0.queueName) }
            },
            sort: { $0.queueName.localizedStandardCompare($1.queueName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreQueueName,
               let queue = items.first(where: { $0.queueName == savedName }) {
                selectedQueueIDs = [queue.id]
                activeQueue = queue
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let queue = items.first(where: { $0.queueName == name }) {
                selectedQueueIDs = [queue.id]
                activeQueue = queue
                pendingSelectName = nil
            }
            await fetchMessageCounts()
        }
    }

    private func fetchMessageCounts() async {
        let results = await withTaskGroup(of: (String, Int?).self, returning: [String: Int].self) { group in
            var inFlight = 0
            var queueIterator = queues.makeIterator()

            // Seed initial batch (max 10 concurrent)
            for _ in 0..<min(10, queues.count) {
                if let queue = queueIterator.next() {
                    inFlight += 1
                    let url = queue.queueUrl
                    let name = queue.queueName
                    group.addTask { [service] in
                        do {
                            let attrs = try await service.getQueueAttributes(
                                queueUrl: url,
                                attributeNames: ["ApproximateNumberOfMessages"]
                            )
                            let count = Int(attrs["ApproximateNumberOfMessages"] ?? "") ?? 0
                            return (url, count)
                        } catch {
                            Log.warn("Failed to fetch message count for \(name): \(error.localizedDescription)", category: "SQS")
                            return (url, nil)
                        }
                    }
                }
            }

            var collected: [String: Int] = [:]
            for await (url, count) in group {
                inFlight -= 1
                if let count { collected[url] = count }
                if let queue = queueIterator.next() {
                    inFlight += 1
                    let nextUrl = queue.queueUrl
                    let nextName = queue.queueName
                    group.addTask { [service] in
                        do {
                            let attrs = try await service.getQueueAttributes(
                                queueUrl: nextUrl,
                                attributeNames: ["ApproximateNumberOfMessages"]
                            )
                            let count = Int(attrs["ApproximateNumberOfMessages"] ?? "") ?? 0
                            return (nextUrl, count)
                        } catch {
                            Log.warn("Failed to fetch message count for \(nextName): \(error.localizedDescription)", category: "SQS")
                            return (nextUrl, nil)
                        }
                    }
                }
            }
            return collected
        }

        for (url, count) in results {
            messageCounts[url] = count
        }
    }

    private func deleteQueues(_ targets: [SQSQueue]) {
        Task {
            selectedQueueIDs.subtract(Set(targets.map(\.id)))
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteQueue(queueUrl: $0.queueUrl)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .sqs, by: deleted.count)
                selectedQueueIDs.subtract(deleted)
                if let active = activeQueue, deleted.contains(active.id) { activeQueue = nil }

                // SQS DeleteQueue is eventually consistent: ListQueues can
                // keep returning the deleted queue for up to 60 seconds.
                // Optimistically remove from the local list and remember the
                // names so we can filter them out of any refetches during
                // that window.
                let deletedNames = targets
                    .filter { deleted.contains($0.id) }
                    .map(\.queueName)
                recentlyDeletedNames.formUnion(deletedNames)
                loader.items.removeAll { deletedNames.contains($0.queueName) }

                // Clear the filter after 60s.
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    recentlyDeletedNames.subtract(deletedNames)
                }

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
