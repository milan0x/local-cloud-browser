import SwiftUI
import AppKit

struct SNSTopicListView: View {
    @ObservedObject var service: SNSService
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTopicIDs: Set<SNSTopic.ID>
    @Binding var activeTopic: SNSTopic?
    var restoreTopicArn: String?

    @StateObject private var loader = ListLoader<SNSTopic>()
    private var topics: [SNSTopic] { loader.items }
    @State private var subscriptionCounts: [String: Int] = [:]  // topicArn -> count
    @State private var showCreateSheet = false
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
            SNSCreateTopicView(service: service, existingTopicNames: Set(loader.items.map(\.topicName)))
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
            loadTopics(force: true)
        }
        .syncSelection(selectedTopicIDs, items: topics, activeItem: $activeTopic)
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
            deleteDisabled: topicDeleteDisabled,
            deleteHelp: selectedTopicIDs.count <= 1 ? "Delete Topic" : "Delete \(selectedTopicIDs.count) Topics",
            onRefresh: { loadTopics(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { topicsToDelete = topics.filter { selectedTopicIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var topicListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: topics.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading topics...", onRetry: { loadTopics(force: true) }) {
            VStack(spacing: 0) {
                if topics.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter topics")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedTopicIDs) {
                    if topics.isEmpty {
                        EmptyStateView(icon: "bell", message: "No topics")
                            .listRowSeparator(.hidden)
                    }
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
                .foregroundStyle(selectedTopicIDs.contains(topic.id) ? Color.white : Color.primary)
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
            .background(DoubleClickDetector {
                if selectedTopicIDs.count == 1,
                   let id = selectedTopicIDs.first,
                   let topic = topics.first(where: { $0.id == id }) {
                    topicToShowAttributes = topic
                }
            })
            }
        }
    }

    // MARK: - Data

    private func loadTopics(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listTopics() },
            sort: { $0.topicName.localizedStandardCompare($1.topicName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedArn = restoreTopicArn,
               let topic = items.first(where: { $0.topicArn == savedArn }) {
                selectedTopicIDs = [topic.id]
                activeTopic = topic
            }
            loader.hasRestoredSession = true
            await fetchSubscriptionCounts()
        }
    }

    private func fetchSubscriptionCounts() async {
        for topic in topics {
            do {
                let attrs = try await service.getTopicAttributes(topicArn: topic.topicArn)
                let count = Int(attrs["SubscriptionsConfirmed"] ?? "") ?? 0
                subscriptionCounts[topic.topicArn] = count
            } catch {
                Log.warn("Failed to fetch subscription count for \(topic.topicName): \(error.localizedDescription)", category: "SNS")
            }
        }
    }

    private func deleteTopics(_ targets: [SNSTopic]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteTopic(topicArn: $0.topicArn)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedTopicIDs.subtract(deleted)
                if let active = activeTopic, deleted.contains(active.id) { activeTopic = nil }
                loadTopics(force: true)
            }
        }
    }

}
