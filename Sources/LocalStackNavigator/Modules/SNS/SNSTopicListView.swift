import SwiftUI
import AppKit

struct SNSTopicListView: View {
    @ObservedObject var service: SNSService
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTopicIDs: Set<SNSTopic.ID>
    @Binding var activeTopic: SNSTopic?
    var restoreTopicArn: String?

    @State private var topics: [SNSTopic] = []
    @State private var hasRestoredSession = false
    @State private var subscriptionCounts: [String: Int] = [:]  // topicArn -> count
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var topicsToDelete: [SNSTopic] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var topicToShowAttributes: SNSTopic?

    var body: some View {
        VStack(spacing: 0) {
            topicListHeader
            Divider()
            topicListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SNSCreateTopicView(service: service, existingTopicNames: Set(topics.map(\.topicName)))
                .onDisappear { loadTopics(force: true) }
        }
        .alert(
            topicsToDelete.count == 1
                ? "Delete Topic"
                : "Delete \(topicsToDelete.count) Topics",
            isPresented: Binding(
                get: { !topicsToDelete.isEmpty },
                set: { if !$0 { topicsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteTopics(topicsToDelete)
            }
            Button("Cancel", role: .cancel) {
                topicsToDelete = []
            }
        } message: {
            if topicsToDelete.count == 1, let topic = topicsToDelete.first {
                Text("Are you sure you want to delete \"\(topic.topicName)\"?\n\nAll subscriptions will be removed. This cannot be undone.")
            } else {
                let names = topicsToDelete.map(\.topicName).joined(separator: "\n")
                Text("Are you sure you want to delete these topics?\n\n\(names)\n\nAll subscriptions will be removed. This cannot be undone.")
            }
        }
        .sheet(item: $topicToShowAttributes) { topic in
            SNSTopicAttributesView(service: service, topic: topic)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadTopics() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && topicsToDelete.isEmpty && topicToShowAttributes == nil && !isLoading }) {
            loadTopics(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedTopicIDs = []
            activeTopic = nil
            topics = []
            subscriptionCounts = [:]
            loadTopics(force: true)
        }
        .syncSelection(selectedTopicIDs, items: topics, activeItem: $activeTopic)
    }

    private var topicDeleteDisabled: Bool {
        appState.isReadOnly || selectedTopicIDs.isEmpty
    }

    // MARK: - Header

    private var topicListHeader: some View {
        HStack {
            Text("Topics")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadTopics(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadTopics(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: topicDeleteDisabled, help: selectedTopicIDs.count <= 1 ? "Delete Topic" : "Delete \(selectedTopicIDs.count) Topics") {
                topicsToDelete = topics.filter { selectedTopicIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var topicListContent: some View {
        if isLoading && topics.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading topics...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadTopics(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if topics.isEmpty {
            EmptyStateView(icon: "bell", message: "No topics")
            .contextMenu {
                Button("Create Topic") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            List(topics, selection: $selectedTopicIDs) { topic in
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
            .overlay(alignment: .bottom) {
                if errorMessage != nil {
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

    // MARK: - Data

    private func loadTopics(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listTopics()
                let freshTopics = loaded.sorted { $0.topicName.localizedStandardCompare($1.topicName) == .orderedAscending }
                if topics != freshTopics {
                    topics = freshTopics
                }
                if !hasRestoredSession, let savedArn = restoreTopicArn,
                   let topic = topics.first(where: { $0.topicArn == savedArn }) {
                    selectedTopicIDs = [topic.id]
                    activeTopic = topic
                }
                hasRestoredSession = true
                await fetchSubscriptionCounts()
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
            var deletedIDs: Set<SNSTopic.ID> = []
            for topic in targets {
                do {
                    try await service.deleteTopic(topicArn: topic.topicArn)
                    deletedIDs.insert(topic.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedTopicIDs.subtract(deletedIDs)
                if let active = activeTopic, deletedIDs.contains(active.id) {
                    activeTopic = nil
                }
                loadTopics(force: true)
            }
        }
    }
}
