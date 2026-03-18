import SwiftUI
import AppKit

struct SESIdentityListView: View {
    @ObservedObject var service: SESService
    @ObservedObject var toolbarState: SESToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedIdentityIDs: Set<SESIdentity.ID>
    @Binding var activeIdentity: SESIdentity?
    var restoreIdentityName: String?

    @StateObject private var loader = PaginatedListLoader<SESIdentity>()
    private var identities: [SESIdentity] { loader.items }
    @State private var showVerifySheet = false
    @State private var identitiesToDelete: [SESIdentity] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?

    var body: some View {
        VStack(spacing: 0) {
            identityListHeader
            Divider()
            identityListContent
        }
        .sheet(isPresented: $showVerifySheet) {
            SESVerifyIdentityView(
                service: service,
                existingIdentities: loader.items.map(\.identity),
                onCreate: { pendingSelectName = $0 }
            )
            .onDisappear { loadIdentities(force: true) }
        }
        .deleteConfirmation(items: $identitiesToDelete, noun: "Identity", pluralNoun: "Identities") { items in
            if items.count == 1, let identity = items.first {
                Text("Are you sure you want to delete \"\(identity.identity)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) identities?")
            }
        } onDelete: { deleteIdentities($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadIdentities() }
        .onAutoRefresh(canRefresh: { !showVerifySheet && identitiesToDelete.isEmpty && !loader.isLoading }) {
            loadIdentities(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedIdentityIDs = []
            activeIdentity = nil
            loader.items = []
            loadIdentities(force: true)
        }
        .syncSelection(selectedIdentityIDs, items: identities, activeItem: $activeIdentity)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .verifyIdentity:
                toolbarState.pendingAction = nil
                showVerifySheet = true
            case .deleteIdentity:
                toolbarState.pendingAction = nil
                if let active = activeIdentity {
                    identitiesToDelete = [active]
                }
            case .sendEmail, .clearSentEmails:
                break // handled by sent email browser
            }
        }
    }

    private var identityDeleteDisabled: Bool {
        appState.isReadOnly || selectedIdentityIDs.isEmpty
    }

    private var filteredIdentities: [SESIdentity] {
        guard !searchText.isEmpty else { return identities }
        let query = searchText.lowercased()
        return identities.filter {
            $0.identity.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var identityListHeader: some View {
        ListHeaderBar(
            title: "Identities",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: identities.count,
            deleteDisabled: identityDeleteDisabled,
            deleteHelp: selectedIdentityIDs.count <= 1 ? "Delete Identity" : "Delete \(selectedIdentityIDs.count) Identities",
            onRefresh: { loadIdentities(force: true) },
            onCreate: { showVerifySheet = true },
            onDelete: { identitiesToDelete = identities.filter { selectedIdentityIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var identityListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: identities.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading identities...", emptyIcon: "envelope", emptyMessage: "No identities", onRetry: { loadIdentities(force: true) }) {
            VStack(spacing: 0) {
                if identities.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter identities")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedIdentityIDs) {
                    ForEach(filteredIdentities) { identity in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(identity.identity)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                        Spacer()
                        typeBadge(for: identity)
                        verifiedBadge
                    }
                    .selectionForeground()
                    .tag(identity.id)
                    .contextMenu {
                        Button("Copy Identity") { copyToClipboard(identity.identity) }
                        Menu("Copy as AWS CLI") {
                            Button("Delete Identity") {
                                copyToClipboard(identity.deleteIdentityCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Send Email") {
                                copyToClipboard(identity.sendEmailCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Identities") {
                                copyToClipboard(SESIdentity.listIdentitiesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Verify Identity") {
                            showVerifySheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedIdentityIDs.count > 1 && selectedIdentityIDs.contains(identity.id) {
                            let selected = identities.filter { selectedIdentityIDs.contains($0.id) }
                            Button("Delete (\(selected.count) Identities)", role: .destructive) {
                                identitiesToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                identitiesToDelete = [identity]
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
                    Button("Verify Identity") {
                        showVerifySheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

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

                if filteredIdentities.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.identity.lowercased().contains(query) }
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

                ListStatusBar(totalCount: identities.count, selectedCount: selectedIdentityIDs.count, noun: "identity", pluralNoun: "identities", hasMorePages: loader.hasMorePages)
            }
        }
    }

    private func typeBadge(for identity: SESIdentity) -> some View {
        StatusBadge(text: identity.typeBadge, color: identity.isEmail ? .blue : .purple)
    }

    private var verifiedBadge: some View {
        StatusBadge(text: "Verified", color: .green)
    }

    // MARK: - Data

    private func loadIdentities(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listIdentitiesPage(token: token) },
            sort: { $0.identity.localizedStandardCompare($1.identity) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreIdentityName,
               let identity = items.first(where: { $0.identity == savedName }) {
                selectedIdentityIDs = [identity.id]
                activeIdentity = identity
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let identity = items.first(where: { $0.identity == name }) {
                selectedIdentityIDs = [identity.id]
                activeIdentity = identity
                pendingSelectName = nil
            }
        }
    }

    private func deleteIdentities(_ targets: [SESIdentity]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteIdentity(identity: $0.identity)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .ses, by: deleted.count)
                selectedIdentityIDs.subtract(deleted)
                if let active = activeIdentity, deleted.contains(active.id) {
                    activeIdentity = nil
                }
                loadIdentities(force: true)
            }
        }
    }

}
