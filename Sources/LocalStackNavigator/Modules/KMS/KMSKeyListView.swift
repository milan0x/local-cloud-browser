import SwiftUI
import AppKit

struct KMSKeyListView: View {
    @ObservedObject var service: KMSService
    @ObservedObject var toolbarState: KMSToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedKeyIDs: Set<KMSKey.ID>
    @Binding var activeKey: KMSKey?
    var restoreKeyId: String?

    @State private var keys: [KMSKey] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var keysToDelete: [KMSKey] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var keyToShowDetail: KMSKey?
    @State private var searchText = ""

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
        .alert(
            keysToDelete.count == 1
                ? "Schedule Key Deletion"
                : "Schedule \(keysToDelete.count) Key Deletions",
            isPresented: Binding(
                get: { !keysToDelete.isEmpty },
                set: { if !$0 { keysToDelete = [] } }
            )
        ) {
            Button("Schedule Deletion", role: .destructive) {
                deleteKeys(keysToDelete)
            }
            Button("Cancel", role: .cancel) {
                keysToDelete = []
            }
        } message: {
            if keysToDelete.count == 1, let key = keysToDelete.first {
                Text("Are you sure you want to schedule deletion for key \"\(key.truncatedId)\"?\n\nThe key will be deleted after a waiting period.")
            } else {
                Text("Are you sure you want to schedule deletion for \(keysToDelete.count) keys?\n\nThe keys will be deleted after a waiting period.")
            }
        }
        .sheet(item: $keyToShowDetail) { key in
            KMSKeyDetailSheet(service: service, key: key)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadKeys() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && keysToDelete.isEmpty && keyToShowDetail == nil && !isLoading }) {
            loadKeys(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedKeyIDs = []
            activeKey = nil
            keys = []
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
        HStack {
            Text("Keys")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadKeys(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadKeys(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: keyDeleteDisabled, help: selectedKeyIDs.count <= 1 ? "Schedule Key Deletion" : "Schedule \(selectedKeyIDs.count) Key Deletions") {
                keysToDelete = keys.filter { selectedKeyIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var keyListContent: some View {
        if isLoading && keys.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading keys...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, keys.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadKeys(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if keys.isEmpty {
            EmptyStateView(icon: "lock.shield", message: "No keys")
            .contextMenu {
                Button("Create Key") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if keys.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter keys")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredKeys, selection: $selectedKeyIDs) { key in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
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

                // Status bar
                Divider()
                HStack {
                    Text("\(keys.count) key\(keys.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedKeyIDs.count > 1 {
                        Text("(\(selectedKeyIDs.count) selected)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
                let loaded = try await service.listKeys()
                let freshKeys = loaded.sorted { ($0.description.isEmpty ? $0.keyId : $0.description).localizedStandardCompare($1.description.isEmpty ? $1.keyId : $1.description) == .orderedAscending }
                if keys != freshKeys {
                    keys = freshKeys
                }
                if !hasRestoredSession, let savedId = restoreKeyId,
                   let key = keys.first(where: { $0.keyId == savedId }) {
                    selectedKeyIDs = [key.id]
                    activeKey = key
                }
                hasRestoredSession = true
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

    private func deleteKeys(_ targets: [KMSKey]) {
        Task {
            var deletedIDs: Set<KMSKey.ID> = []
            for key in targets {
                do {
                    try await service.scheduleKeyDeletion(keyId: key.keyId)
                    deletedIDs.insert(key.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
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
