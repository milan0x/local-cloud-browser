import SwiftUI
import AppKit

struct SecretsListView: View {
    @ObservedObject var service: SecretsManagerService
    @ObservedObject var toolbarState: SecretsManagerToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSecretIDs: Set<Secret.ID>
    @Binding var activeSecret: Secret?
    var restoreSecretName: String?

    @State private var showCreateSheet = false
    @State private var pendingSelectName: String?
    @State private var secretsToDelete: [Secret] = []
    @State private var serviceError: ServiceError?
    @State private var secretToShowDetail: Secret?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<Secret>()
    private var secrets: [Secret] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            secretListHeader
            Divider()
            secretListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSecretView(service: service, existingSecretNames: Set(secrets.map(\.name))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadSecrets(force: true) }
        }
        .deleteConfirmation(items: $secretsToDelete, noun: "Secret") { items in
            if items.count == 1, let secret = items.first {
                Text("Are you sure you want to delete \"\(secret.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these secrets?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteSecrets($0) }
        .sheet(item: $secretToShowDetail) { secret in
            SecretDetailView(service: service, secret: secret)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadSecrets() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && secretsToDelete.isEmpty && secretToShowDetail == nil && !loader.isLoading }) {
            loadSecrets(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedSecretIDs = []
            activeSecret = nil
            loader.items = []
            loadSecrets(force: true)
        }
        .syncSelection(selectedSecretIDs, items: secrets, activeItem: $activeSecret)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createSecret:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeSecret {
                    secretsToDelete = [active]
                }
            case .viewDetails:
                break // handled by right pane
            }
        }
    }

    private var secretDeleteDisabled: Bool {
        appState.isReadOnly || selectedSecretIDs.isEmpty
    }

    private var filteredSecrets: [Secret] {
        guard !searchText.isEmpty else { return secrets }
        let query = searchText.lowercased()
        return secrets.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Header

    private var secretListHeader: some View {
        ListHeaderBar(
            title: "Secrets",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: secretDeleteDisabled,
            deleteHelp: selectedSecretIDs.count <= 1 ? "Delete Secret" : "Delete \(selectedSecretIDs.count) Secrets",
            onRefresh: { loadSecrets(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { secretsToDelete = secrets.filter { selectedSecretIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var secretListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: secrets.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading secrets...", onRetry: { loadSecrets(force: true) }) {
            VStack(spacing: 0) {
                if secrets.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter secrets")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedSecretIDs) {
                    if secrets.isEmpty {
                        EmptyStateView(icon: "key", message: "No secrets")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredSecrets) { secret in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(secret.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let desc = secret.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .selectionForeground()
                    .tag(secret.id)
                    .contextMenu {
                        Button("View Details") {
                            secretToShowDetail = secret
                        }
                        Divider()
                        Button("Copy ARN") { copyToClipboard(secret.arn) }
                        Button("Copy Name") { copyToClipboard(secret.name) }
                        Menu("Copy as AWS CLI") {
                            Button("Get Secret Value") {
                                copyToClipboard(secret.getSecretValueCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Describe Secret") {
                                copyToClipboard(secret.describeSecretCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Secret") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedSecretIDs.count > 1 && selectedSecretIDs.contains(secret.id) {
                            let selected = secrets.filter { selectedSecretIDs.contains($0.id) }
                            Button("Delete \(selected.count) Secrets", role: .destructive) {
                                secretsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                secretsToDelete = [secret]
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
                    Button("Create Secret") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedSecretIDs.count == 1,
                       let id = selectedSecretIDs.first,
                       let secret = secrets.first(where: { $0.id == id }) {
                        secretToShowDetail = secret
                    }
                })

                ListStatusBar(totalCount: secrets.count, selectedCount: selectedSecretIDs.count, noun: "secret")
            }
        }
    }

    // MARK: - Data

    private func loadSecrets(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listSecrets() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreSecretName,
               let secret = items.first(where: { $0.name == savedName }) {
                selectedSecretIDs = [secret.id]
                activeSecret = secret
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let secret = items.first(where: { $0.name == name }) {
                selectedSecretIDs = [secret.id]
                activeSecret = secret
                pendingSelectName = nil
            }
        }
    }

    private func deleteSecrets(_ targets: [Secret]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteSecret(secretId: $0.arn)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedSecretIDs.subtract(deleted)
                if let active = activeSecret, deleted.contains(active.id) {
                    activeSecret = nil
                }
                loadSecrets(force: true)
            }
        }
    }

}
