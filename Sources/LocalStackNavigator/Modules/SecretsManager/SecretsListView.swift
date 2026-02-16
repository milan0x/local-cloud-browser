import SwiftUI
import AppKit

struct SecretsListView: View {
    @ObservedObject var service: SecretsManagerService
    @ObservedObject var toolbarState: SecretsManagerToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSecretIDs: Set<Secret.ID>
    @Binding var activeSecret: Secret?
    var restoreSecretName: String?

    @State private var secrets: [Secret] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var secretsToDelete: [Secret] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var secretToShowDetail: Secret?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            secretListHeader
            Divider()
            secretListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSecretView(service: service, existingSecretNames: Set(secrets.map(\.name)))
                .onDisappear { loadSecrets(force: true) }
        }
        .alert(
            secretsToDelete.count == 1
                ? "Delete Secret"
                : "Delete \(secretsToDelete.count) Secrets",
            isPresented: Binding(
                get: { !secretsToDelete.isEmpty },
                set: { if !$0 { secretsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteSecrets(secretsToDelete)
            }
            Button("Cancel", role: .cancel) {
                secretsToDelete = []
            }
        } message: {
            if secretsToDelete.count == 1, let secret = secretsToDelete.first {
                Text("Are you sure you want to delete \"\(secret.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = secretsToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these secrets?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $secretToShowDetail) { secret in
            SecretDetailView(service: service, secret: secret)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadSecrets() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && secretsToDelete.isEmpty && secretToShowDetail == nil && !isLoading }) {
            loadSecrets(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedSecretIDs = []
            activeSecret = nil
            secrets = []
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
        HStack {
            Text("Secrets")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadSecrets(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadSecrets(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: secretDeleteDisabled, help: selectedSecretIDs.count <= 1 ? "Delete Secret" : "Delete \(selectedSecretIDs.count) Secrets") {
                secretsToDelete = secrets.filter { selectedSecretIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var secretListContent: some View {
        if isLoading && secrets.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading secrets...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, secrets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadSecrets(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if secrets.isEmpty {
            EmptyStateView(icon: "key", message: "No secrets")
            .contextMenu {
                Button("Create Secret") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if secrets.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter secrets")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredSecrets, selection: $selectedSecretIDs) { secret in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
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

                // Status bar
                Divider()
                HStack {
                    Text("\(secrets.count) secret\(secrets.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedSecretIDs.count > 1 {
                        Text("(\(selectedSecretIDs.count) selected)")
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

    // MARK: - Data

    private func loadSecrets(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listSecrets()
                let freshSecrets = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if secrets != freshSecrets {
                    secrets = freshSecrets
                }
                if !hasRestoredSession, let savedName = restoreSecretName,
                   let secret = secrets.first(where: { $0.name == savedName }) {
                    selectedSecretIDs = [secret.id]
                    activeSecret = secret
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

    private func deleteSecrets(_ targets: [Secret]) {
        Task {
            var deletedIDs: Set<Secret.ID> = []
            for secret in targets {
                do {
                    try await service.deleteSecret(secretId: secret.arn)
                    deletedIDs.insert(secret.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedSecretIDs.subtract(deletedIDs)
                if let active = activeSecret, deletedIDs.contains(active.id) {
                    activeSecret = nil
                }
                loadSecrets(force: true)
            }
        }
    }
}
