import SwiftUI
import AppKit

struct SNSSubscriptionListView: View {
    @ObservedObject var service: SNSService
    let topic: SNSTopic
    @ObservedObject var toolbarState: SNSToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var subscriptions: [SNSSubscription] = []
    @State private var selectedSubscriptionIDs: Set<SNSSubscription.ID> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serviceError: ServiceError?
    @State private var searchQuery = ""
    @State private var showPublishSheet = false
    @State private var showSubscribeSheet = false
    @State private var showAttributesSheet = false
    @State private var subscriptionsToDelete: [SNSSubscription] = []
    @State private var lastLoadTime: Date?
    @State private var detailSubscription: SNSSubscription?

    private var sortedSubscriptions: [SNSSubscription] {
        let filtered: [SNSSubscription]
        if searchQuery.isEmpty {
            filtered = subscriptions
        } else {
            let query = searchQuery.lowercased()
            filtered = subscriptions.filter {
                $0.protocol_.lowercased().contains(query)
                    || $0.endpoint.lowercased().contains(query)
                    || $0.subscriptionArn.lowercased().contains(query)
            }
        }
        return filtered.sorted { $0.protocol_ < $1.protocol_ }
    }

    var body: some View {
        VStack(spacing: 0) {
            subscriptionHeader
            Divider()
            subscriptionContent
            Divider()
            subscriptionStatusBar
        }
        .sheet(isPresented: $showPublishSheet) {
            SNSPublishMessageView(service: service, topic: topic)
        }
        .sheet(isPresented: $showSubscribeSheet) {
            SNSCreateSubscriptionView(service: service, topic: topic)
                .onDisappear { loadSubscriptions(force: true) }
        }
        .sheet(isPresented: $showAttributesSheet) {
            SNSTopicAttributesView(service: service, topic: topic)
        }
        .sheet(item: $detailSubscription) { sub in
            SNSSubscriptionAttributesView(service: service, subscription: sub)
        }
        .alert(
            subscriptionsToDelete.count == 1
                ? "Unsubscribe"
                : "Unsubscribe \(subscriptionsToDelete.count) Subscriptions",
            isPresented: Binding(
                get: { !subscriptionsToDelete.isEmpty },
                set: { if !$0 { subscriptionsToDelete = [] } }
            )
        ) {
            Button("Unsubscribe", role: .destructive) {
                unsubscribeAll(subscriptionsToDelete)
            }
            Button("Cancel", role: .cancel) {
                subscriptionsToDelete = []
            }
        } message: {
            if subscriptionsToDelete.count == 1, let sub = subscriptionsToDelete.first {
                Text("Remove subscription for \(sub.protocol_):\(sub.endpoint)?\n\nThis cannot be undone.")
            } else {
                Text("Remove \(subscriptionsToDelete.count) subscriptions?\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task(id: topic.id) {
            subscriptions = []
            selectedSubscriptionIDs = []
            lastLoadTime = nil
            loadSubscriptions()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showPublishSheet && !showSubscribeSheet && !showAttributesSheet && detailSubscription == nil && subscriptionsToDelete.isEmpty && !isLoading else { return }
            loadSubscriptions(force: true, silent: true)
        }
        .onChange(of: selectedSubscriptionIDs) {
            toolbarState.hasSubscriptionSelection = !selectedSubscriptionIDs.isEmpty
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            toolbarState.pendingAction = nil
            switch action {
            case .publish:
                showPublishSheet = true
            case .subscribe:
                showSubscribeSheet = true
            case .showAttributes:
                showAttributesSheet = true
            case .unsubscribeSelected:
                let selected = subscriptions.filter { selectedSubscriptionIDs.contains($0.id) }
                if !selected.isEmpty { subscriptionsToDelete = selected }
            }
        }
    }

    // MARK: - Header

    private var subscriptionHeader: some View {
        HStack {
            Text(topic.topicName)
                .font(.headline)
                .lineLimit(1)

            Text(topic.isFifo ? "FIFO" : "Standard")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(topic.isFifo ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(topic.isFifo ? .blue : .secondary)

            Spacer()

            SearchBarView(query: $searchQuery, placeholder: "Search subscriptions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var subscriptionContent: some View {
        if isLoading && subscriptions.isEmpty {
            ProgressView("Loading subscriptions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadSubscriptions(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if subscriptions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No subscriptions")
                    .foregroundStyle(.secondary)
                Text("Add a subscription to receive notifications from this topic.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedSubscriptions, selection: $selectedSubscriptionIDs) {
                TableColumn("Protocol") { sub in
                    Text(sub.protocol_)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 60, ideal: 80)

                TableColumn("Endpoint") { sub in
                    Text(sub.endpoint)
                        .lineLimit(1)
                        .help(sub.endpoint)
                }
                .width(min: 150)

                TableColumn("Status") { sub in
                    if sub.isPending {
                        Text("Pending")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    } else {
                        Text("Confirmed")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                .width(min: 70, ideal: 85)

                TableColumn("Subscription ARN") { sub in
                    Text(sub.truncatedArn)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(sub.subscriptionArn)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Actions") { sub in
                    HStack(spacing: 8) {
                        if !sub.isPending {
                            Button {
                                detailSubscription = sub
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("View Attributes")
                        }

                        Button {
                            copyToClipboard(sub.endpoint)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy Endpoint")

                        Button(role: .destructive) {
                            subscriptionsToDelete = [sub]
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(appState.isReadOnly || sub.isPending ? .gray : .red)
                        }
                        .buttonStyle(.borderless)
                        .help("Unsubscribe")
                        .disabled(appState.isReadOnly || sub.isPending)
                    }
                }
                .width(min: 80, ideal: 110)
            }
            .contextMenu(forSelectionType: SNSSubscription.ID.self) { selection in
                if let id = selection.first, let sub = subscriptions.first(where: { $0.id == id }) {
                    if selection.count == 1 && !sub.isPending {
                        Button("View Attributes") { detailSubscription = sub }
                        Divider()
                    }
                    Button("Copy Subscription ARN") { copyToClipboard(sub.subscriptionArn) }
                    Button("Copy Endpoint") { copyToClipboard(sub.endpoint) }
                    Button("Copy Protocol") { copyToClipboard(sub.protocol_) }
                    if selection.count == 1 && !sub.isPending {
                        Menu("Copy as AWS CLI") {
                            Button("Get Subscription Attributes") {
                                copyToClipboard(sub.getAttributesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                    }
                    Divider()
                    if selection.count > 1 {
                        let selected = subscriptions.filter { selection.contains($0.id) && !$0.isPending }
                        Button("Unsubscribe \(selected.count) Subscriptions", role: .destructive) {
                            subscriptionsToDelete = selected
                        }
                        .disabled(appState.isReadOnly || selected.isEmpty)
                    } else {
                        Button("Unsubscribe", role: .destructive) {
                            subscriptionsToDelete = [sub]
                        }
                        .disabled(appState.isReadOnly || sub.isPending)
                    }
                }
            } primaryAction: { selection in
                guard let id = selection.first,
                      let sub = subscriptions.first(where: { $0.id == id }),
                      !sub.isPending else { return }
                detailSubscription = sub
            }
        }
    }

    // MARK: - Status Bar

    private var subscriptionStatusBar: some View {
        HStack {
            Text("\(subscriptions.count) subscription\(subscriptions.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !searchQuery.isEmpty {
                Text("(\(sortedSubscriptions.count) shown)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if selectedSubscriptionIDs.count > 1 {
                Text("(\(selectedSubscriptionIDs.count) selected)")
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

    // MARK: - Data

    private func loadSubscriptions(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listSubscriptions(topicArn: topic.topicArn)
                if subscriptions != loaded {
                    subscriptions = loaded
                }
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

    private func unsubscribeAll(_ targets: [SNSSubscription]) {
        Task {
            var deletedIDs: Set<SNSSubscription.ID> = []
            for sub in targets {
                guard !sub.isPending else { continue }
                do {
                    try await service.unsubscribe(subscriptionArn: sub.subscriptionArn)
                    deletedIDs.insert(sub.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                subscriptions.removeAll { deletedIDs.contains($0.id) }
                selectedSubscriptionIDs.subtract(deletedIDs)
            }
        }
    }
}
