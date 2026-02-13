import SwiftUI
import AppKit

struct SQSQueueListView: View {
    @ObservedObject var service: SQSService
    @EnvironmentObject private var appState: AppState
    @Binding var selectedQueueIDs: Set<SQSQueue.ID>
    @Binding var activeQueue: SQSQueue?
    var restoreQueueName: String?

    @State private var queues: [SQSQueue] = []
    @State private var hasRestoredSession = false
    @State private var messageCounts: [String: Int] = [:]  // queueUrl -> count
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var queuesToDelete: [SQSQueue] = []
    @State private var queueToPurge: SQSQueue?
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
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
        .alert(
            queuesToDelete.count == 1
                ? "Delete Queue"
                : "Delete \(queuesToDelete.count) Queues",
            isPresented: Binding(
                get: { !queuesToDelete.isEmpty },
                set: { if !$0 { queuesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteQueues(queuesToDelete)
            }
            Button("Cancel", role: .cancel) {
                queuesToDelete = []
            }
        } message: {
            if queuesToDelete.count == 1, let queue = queuesToDelete.first {
                Text("Are you sure you want to delete \"\(queue.queueName)\"?\n\nThis cannot be undone.")
            } else {
                let names = queuesToDelete.map(\.queueName).joined(separator: "\n")
                Text("Are you sure you want to delete these queues?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
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
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && queuesToDelete.isEmpty && queueToPurge == nil && queueToShowAttributes == nil && !isLoading else { return }
            loadQueues(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedQueueIDs = []
            activeQueue = nil
            queues = []
            messageCounts = [:]
            loadQueues(force: true)
        }
        .onChange(of: appState.region) {
            selectedQueueIDs = []
            activeQueue = nil
            queues = []
            messageCounts = [:]
            loadQueues(force: true)
        }
        .onChange(of: selectedQueueIDs) {
            if selectedQueueIDs.count == 1, let id = selectedQueueIDs.first {
                activeQueue = queues.first { $0.id == id }
            } else {
                activeQueue = nil
            }
        }
    }

    private var queueDeleteDisabled: Bool {
        appState.isReadOnly || selectedQueueIDs.isEmpty
    }

    // MARK: - Header

    private var queueListHeader: some View {
        HStack {
            Text("Queues")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadQueues(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadQueues(force: true)
            }

            Button {
                queuesToDelete = queues.filter { selectedQueueIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(queueDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(queueDeleteDisabled)
            .help(selectedQueueIDs.count <= 1 ? "Delete Queue" : "Delete \(selectedQueueIDs.count) Queues")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var queueListContent: some View {
        if isLoading && queues.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading queues...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadQueues(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if queues.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.2")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No queues")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Queue") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            List(queues, selection: $selectedQueueIDs) { queue in
                VStack(alignment: .leading, spacing: 3) {
                    Text(queue.queueName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(queue.isFifo ? "FIFO" : "Standard")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(queue.isFifo ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                            .foregroundStyle(queue.isFifo ? .blue : .secondary)
                        if let count = messageCounts[queue.queueUrl] {
                            Text("~\(count) msgs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
            .overlay(alignment: .bottom) {
                if errorMessage != nil {
                    connectionLostBanner
                }
            }
            .contextMenu {
                Button("Create Queue") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
            .background(QueueDoubleClickDetector {
                if selectedQueueIDs.count == 1,
                   let id = selectedQueueIDs.first,
                   let queue = queues.first(where: { $0.id == id }) {
                    queueToShowAttributes = queue
                }
            })
        }
    }

    private var connectionLostBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost — showing cached data")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
    }

    // MARK: - Data

    private func loadQueues(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.listQueues()
                let freshQueues = loaded.sorted { $0.queueName.localizedStandardCompare($1.queueName) == .orderedAscending }
                if queues != freshQueues {
                    queues = freshQueues
                }
                if !hasRestoredSession, let savedName = restoreQueueName,
                   let queue = queues.first(where: { $0.queueName == savedName }) {
                    selectedQueueIDs = [queue.id]
                    activeQueue = queue
                }
                hasRestoredSession = true
                await fetchMessageCounts()
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
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
                // Silently skip — counts are supplementary
            }
        }
    }

    private func deleteQueues(_ targets: [SQSQueue]) {
        Task {
            var deletedIDs: Set<SQSQueue.ID> = []
            for queue in targets {
                do {
                    try await service.deleteQueue(queueUrl: queue.queueUrl)
                    deletedIDs.insert(queue.id)
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
                selectedQueueIDs.subtract(deletedIDs)
                if let active = activeQueue, deletedIDs.contains(active.id) {
                    activeQueue = nil
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
                if let clientError = error as? LocalStackClientError,
                   let parsed = clientError.serviceError {
                    serviceError = parsed
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

/// Detects double-clicks within its own bounds using an NSEvent monitor.
/// Placed as `.background` on the queue list — doesn't intercept clicks,
/// just observes double-clicks to trigger a callback.
private struct QueueDoubleClickDetector: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DoubleClickNSView {
        let view = DoubleClickNSView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class DoubleClickNSView: NSView {
        var onDoubleClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            monitor.flatMap { NSEvent.removeMonitor($0) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, event.window == self.window else { return event }
                let pointInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pointInSelf) {
                    self.onDoubleClick?()
                }
                return event
            }
        }

        override func removeFromSuperview() {
            monitor.flatMap { NSEvent.removeMonitor($0) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
