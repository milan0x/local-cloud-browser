import SwiftUI
import AppKit

struct SNSTopicListView: View {
    @ObservedObject var service: SNSService
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedTopicIDs: Set<SNSTopic.ID>
    @Binding var activeTopic: SNSTopic?
    var restoreTopicArn: String?
    var searchFocusTrigger: Int = 0
    var paneFocusTrigger: Int = 0

    @FocusState private var isListFocused: Bool
    @StateObject private var loader = PaginatedListLoader<SNSTopic>()
    private var topics: [SNSTopic] { loader.items }
    @State private var subscriptionCounts: [String: Int] = [:]  // topicArn -> count
    @State private var subscriptionCountCache: [String: Int] = [:]  // persistent cache across re-renders
    @State private var showCreateSheet = false
    @State private var pendingSelectName: String?
    @State private var topicsToDelete: [SNSTopic] = []
    @State private var serviceError: ServiceError?
    @State private var topicToShowAttributes: SNSTopic?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            topicListHeader
            Divider()
            topicListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SNSCreateTopicView(service: service, existingTopicNames: Set(loader.items.map(\.topicName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadTopics(force: true) }
        }
        .deleteConfirmation(items: $topicsToDelete, noun: "Topic") { items in
            if items.count == 1, let topic = items.first {
                Text("Are you sure you want to delete \"\(topic.topicName)\"?\n\nAll subscriptions will be removed. This cannot be undone.")
            } else {
                let names = items.map(\.topicName).joined(separator: "\n")
                Text("Are you sure you want to delete these topics?\n\n\(names)\n\nAll subscriptions will be removed. This cannot be undone.")
            }
        } onDelete: { deleteTopics($0) }
        .sheet(item: $topicToShowAttributes) { topic in
            SNSTopicAttributesView(service: service, topic: topic)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadTopics() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && topicsToDelete.isEmpty && topicToShowAttributes == nil && !loader.isLoading }) {
            loadTopics(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedTopicIDs = []
            activeTopic = nil
            loader.items = []
            subscriptionCounts = [:]
            subscriptionCountCache = [:]
            loadTopics(force: true)
        }
        .syncSelection(selectedTopicIDs, items: topics, activeItem: $activeTopic)
        .onChange(of: paneFocusTrigger) {
            isListFocused = true
        }
    }

    private var filteredTopics: [SNSTopic] {
        guard !searchText.isEmpty else { return topics }
        let query = searchText.lowercased()
        return topics.filter { $0.topicName.lowercased().contains(query) }
    }

    private var topicDeleteDisabled: Bool {
        appState.isReadOnly || selectedTopicIDs.isEmpty
    }

    // MARK: - Header

    private var topicListHeader: some View {
        ListHeaderBar(
            title: "Topics",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: topics.count,
            deleteDisabled: topicDeleteDisabled,
            deleteHelp: selectedTopicIDs.count <= 1 ? "Delete Topic" : "Delete \(selectedTopicIDs.count) Topics",
            onRefresh: { loadTopics(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { topicsToDelete = topics.filter { selectedTopicIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var topicListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: topics.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading topics...", emptyIcon: "bell", emptyMessage: "No topics", onRetry: { loadTopics(force: true) }) {
            VStack(spacing: 0) {
                if topics.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter topics", focusTrigger: searchFocusTrigger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedTopicIDs) {
                    ForEach(filteredTopics) { topic in
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.topicName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(text: topic.isFifo ? "FIFO" : "Standard", color: topic.isFifo ? .blue : .gray)
                        if let count = subscriptionCounts[topic.topicArn] {
                            Text("\(count) sub\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .selectionForeground()
                .tag(topic.id)
                .contextMenu {
                    Button("View Attributes") {
                        topicToShowAttributes = topic
                    }
                    Divider()
                    Button("Copy Topic ARN") { copyToClipboard(topic.topicArn) }
                    Button("Copy Topic Name") { copyToClipboard(topic.topicName) }
                    Menu("Copy as AWS CLI") {
                        Button("Publish") {
                            copyToClipboard(topic.publishCLI(endpointUrl: appState.endpoint, region: appState.region))
                        }
                        Button("List Subscriptions") {
                            copyToClipboard(topic.listSubscriptionsCLI(endpointUrl: appState.endpoint, region: appState.region))
                        }
                        Button("Get Attributes") {
                            copyToClipboard(topic.getAttributesCLI(endpointUrl: appState.endpoint, region: appState.region))
                        }
                    }
                    Divider()
                    Button("Create Topic") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                    Divider()
                    if selectedTopicIDs.count > 1 && selectedTopicIDs.contains(topic.id) {
                        let selected = topics.filter { selectedTopicIDs.contains($0.id) }
                        Button("Delete \(selected.count) Topics", role: .destructive) {
                            topicsToDelete = selected
                        }
                        .disabled(appState.isReadOnly)
                    } else {
                        Button("Delete", role: .destructive) {
                            topicsToDelete = [topic]
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
                Button("Create Topic") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
            .focused($isListFocused)
            .background(DoubleClickDetector {
                if selectedTopicIDs.count == 1,
                   let id = selectedTopicIDs.first,
                   let topic = topics.first(where: { $0.id == id }) {
                    topicToShowAttributes = topic
                }
            })

                if loader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            loader.loadMore()
                        } label: {
                            if loader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(loader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredTopics.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.topicName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if loader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if loader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Data

    private func loadTopics(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listTopicsPage(token: token) },
            sort: { $0.topicName.localizedStandardCompare($1.topicName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedArn = restoreTopicArn,
               let topic = items.first(where: { $0.topicArn == savedArn }) {
                selectedTopicIDs = [topic.id]
                activeTopic = topic
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let topic = items.first(where: { $0.topicName == name }) {
                selectedTopicIDs = [topic.id]
                activeTopic = topic
                pendingSelectName = nil
            }
            await fetchSubscriptionCounts()
        }
    }

    private func fetchSubscriptionCounts() async {
        // Return cached counts immediately for topics we already know about
        let uncachedTopics = topics.filter { subscriptionCountCache[$0.topicArn] == nil }
        if uncachedTopics.isEmpty && !topics.isEmpty {
            subscriptionCounts = subscriptionCountCache
            return
        }

        // Fetch uncached counts concurrently (max 10 at a time)
        let results = await withTaskGroup(of: (String, Int?).self, returning: [String: Int].self) { group in
            var inFlight = 0
            var topicIterator = uncachedTopics.makeIterator()

            // Seed initial batch
            for _ in 0..<min(10, uncachedTopics.count) {
                if let topic = topicIterator.next() {
                    inFlight += 1
                    let arn = topic.topicArn
                    let name = topic.topicName
                    group.addTask { [service] in
                        do {
                            let attrs = try await service.getTopicAttributes(topicArn: arn)
                            let count = Int(attrs["SubscriptionsConfirmed"] ?? "") ?? 0
                            return (arn, count)
                        } catch {
                            Log.warn("Failed to fetch subscription count for \(name): \(error.localizedDescription)", category: "SNS")
                            return (arn, nil)
                        }
                    }
                }
            }

            var collected: [String: Int] = [:]
            for await (arn, count) in group {
                inFlight -= 1
                if let count { collected[arn] = count }
                // Launch next task to maintain concurrency
                if let topic = topicIterator.next() {
                    inFlight += 1
                    let nextArn = topic.topicArn
                    let nextName = topic.topicName
                    group.addTask { [service] in
                        do {
                            let attrs = try await service.getTopicAttributes(topicArn: nextArn)
                            let count = Int(attrs["SubscriptionsConfirmed"] ?? "") ?? 0
                            return (nextArn, count)
                        } catch {
                            Log.warn("Failed to fetch subscription count for \(nextName): \(error.localizedDescription)", category: "SNS")
                            return (nextArn, nil)
                        }
                    }
                }
            }
            return collected
        }

        // Merge into cache and update visible counts
        for (arn, count) in results {
            subscriptionCountCache[arn] = count
        }
        subscriptionCounts = subscriptionCountCache
    }

    private func deleteTopics(_ targets: [SNSTopic]) {
        Task {
            selectedTopicIDs.subtract(Set(targets.map(\.id)))
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteTopic(topicArn: $0.topicArn)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .sns, by: deleted.count)
                selectedTopicIDs.subtract(deleted)
                if let active = activeTopic, deleted.contains(active.id) { activeTopic = nil }
                loadTopics(force: true)
            }
        }
    }

}
