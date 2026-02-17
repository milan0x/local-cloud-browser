import SwiftUI
import AppKit

struct KMSKeyListView: View {
    @ObservedObject var service: KMSService
    @ObservedObject var toolbarState: KMSToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedKeyIDs: Set<KMSKey.ID>
    @Binding var activeKey: KMSKey?
    var restoreKeyId: String?

    @State private var showCreateSheet = false
    @State private var keysToDelete: [KMSKey] = []
    @State private var serviceError: ServiceError?
    @State private var keyToShowDetail: KMSKey?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<KMSKey>()
    private var keys: [KMSKey] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            keyListHeader
            Divider()
            keyListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            KMSCreateKeyView(service: service)
                .onDisappear { loadKeys(force: true) }
        }
        .deleteConfirmation(items: $keysToDelete, title: { $0 == 1 ? "Schedule Key Deletion" : "Schedule \($0) Key Deletions" }, actionLabel: "Schedule Deletion") { items in
            if items.count == 1, let key = items.first {
                Text("Are you sure you want to schedule deletion for key \"\(key.truncatedId)\"?\n\nThe key will be deleted after a waiting period.")
            } else {
                Text("Are you sure you want to schedule deletion for \(items.count) keys?\n\nThe keys will be deleted after a waiting period.")
            }
        } onDelete: { deleteKeys($0) }
        .sheet(item: $keyToShowDetail) { key in
            KMSKeyDetailSheet(service: service, key: key)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadKeys() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && keysToDelete.isEmpty && keyToShowDetail == nil && !loader.isLoading }) {
            loadKeys(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedKeyIDs = []
            activeKey = nil
            loader.items = []
            loadKeys(force: true)
        }
        .syncSelection(selectedKeyIDs, items: keys, activeItem: $activeKey)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createKey:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .scheduleDeletion:
                toolbarState.pendingAction = nil
                if let active = activeKey {
                    keysToDelete = [active]
                }
            case .viewDetails, .toggleEnabled:
                break // handled by detail pane
            }
        }
    }

    private var keyDeleteDisabled: Bool {
        appState.isReadOnly || selectedKeyIDs.isEmpty
    }

    private var filteredKeys: [KMSKey] {
        guard !searchText.isEmpty else { return keys }
        let query = searchText.lowercased()
        return keys.filter {
            $0.keyId.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var keyListHeader: some View {
        ListHeaderBar(
            title: "Keys",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: keyDeleteDisabled,
            deleteHelp: selectedKeyIDs.count <= 1 ? "Schedule Key Deletion" : "Schedule \(selectedKeyIDs.count) Key Deletions",
            onRefresh: { loadKeys(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { keysToDelete = keys.filter { selectedKeyIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var keyListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: keys.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading keys...", onRetry: { loadKeys(force: true) }) {
            VStack(spacing: 0) {
                if keys.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter keys")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedKeyIDs) {
                    if keys.isEmpty {
                        EmptyStateView(icon: "lock.shield", message: "No keys")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredKeys) { key in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(key.truncatedId)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if !key.description.isEmpty {
                                Text(key.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        stateBadge(for: key)
                    }
                    .foregroundStyle(selectedKeyIDs.contains(key.id) ? Color.white : Color.primary)
                    .tag(key.id)
                    .contextMenu {
                        Button("View Details") {
                            keyToShowDetail = key
                        }
                        Divider()
                        Button("Copy Key ID") { copyToClipboard(key.keyId) }
                        Button("Copy ARN") { copyToClipboard(key.arn) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Key") {
                                copyToClipboard(key.describeKeyCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Keys") {
                                copyToClipboard(KMSKey.listKeysCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Key") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedKeyIDs.count > 1 && selectedKeyIDs.contains(key.id) {
                            let selected = keys.filter { selectedKeyIDs.contains($0.id) }
                            Button("Schedule Deletion (\(selected.count) Keys)", role: .destructive) {
                                keysToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Schedule Deletion", role: .destructive) {
                                keysToDelete = [key]
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
                    Button("Create Key") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedKeyIDs.count == 1,
                       let id = selectedKeyIDs.first,
                       let key = keys.first(where: { $0.id == id }) {
                        keyToShowDetail = key
                    }
                })

                ListStatusBar(totalCount: keys.count, selectedCount: selectedKeyIDs.count, noun: "key")
            }
        }
    }

    private func stateBadge(for key: KMSKey) -> some View {
        StatusBadge(text: key.keyState, color: stateColor(key.keyState))
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "Enabled": .green
        case "Disabled": .orange
        case "PendingDeletion": .red
        default: .gray
        }
    }

    // MARK: - Data

    private func loadKeys(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listKeys() },
            sort: { ($0.description.isEmpty ? $0.keyId : $0.description).localizedStandardCompare($1.description.isEmpty ? $1.keyId : $1.description) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedId = restoreKeyId,
               let key = items.first(where: { $0.keyId == savedId }) {
                selectedKeyIDs = [key.id]
                activeKey = key
            }
            loader.hasRestoredSession = true
        }
    }

    private func deleteKeys(_ targets: [KMSKey]) {
        Task {
            let (deletedIDs, lastError) = await batchDelete(targets) { key in
                try await service.scheduleKeyDeletion(keyId: key.keyId)
            }
            if let lastError { serviceError = lastError }
            if !deletedIDs.isEmpty {
                selectedKeyIDs.subtract(deletedIDs)
                if let active = activeKey, deletedIDs.contains(active.id) {
                    activeKey = nil
                }
                loadKeys(force: true)
            }
        }
    }
}

/// Sheet view for key details (opened via double-click or context menu)
struct KMSKeyDetailSheet: View {
    @ObservedObject var service: KMSService
    let key: KMSKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            KMSKeyDetailPaneView(service: service, key: key, toolbarState: KMSToolbarState())
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
}
