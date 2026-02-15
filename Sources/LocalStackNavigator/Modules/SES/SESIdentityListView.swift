import SwiftUI
import AppKit

struct SESIdentityListView: View {
    @ObservedObject var service: SESService
    @ObservedObject var toolbarState: SESToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedIdentityIDs: Set<SESIdentity.ID>
    @Binding var activeIdentity: SESIdentity?
    var restoreIdentityName: String?

    @State private var identities: [SESIdentity] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showVerifySheet = false
    @State private var identitiesToDelete: [SESIdentity] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            identityListHeader
            Divider()
            identityListContent
        }
        .sheet(isPresented: $showVerifySheet) {
            SESVerifyIdentityView(
                service: service,
                existingIdentities: identities.map(\.identity)
            )
            .onDisappear { loadIdentities(force: true) }
        }
        .alert(
            identitiesToDelete.count == 1
                ? "Delete Identity"
                : "Delete \(identitiesToDelete.count) Identities",
            isPresented: Binding(
                get: { !identitiesToDelete.isEmpty },
                set: { if !$0 { identitiesToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteIdentities(identitiesToDelete)
            }
            Button("Cancel", role: .cancel) {
                identitiesToDelete = []
            }
        } message: {
            if identitiesToDelete.count == 1, let identity = identitiesToDelete.first {
                Text("Are you sure you want to delete \"\(identity.identity)\"?")
            } else {
                Text("Are you sure you want to delete \(identitiesToDelete.count) identities?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadIdentities() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showVerifySheet && identitiesToDelete.isEmpty && !isLoading else { return }
            loadIdentities(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedIdentityIDs = []
            activeIdentity = nil
            identities = []
            loadIdentities(force: true)
        }
        .onChange(of: appState.region) {
            selectedIdentityIDs = []
            activeIdentity = nil
            identities = []
            loadIdentities(force: true)
        }
        .onChange(of: selectedIdentityIDs) {
            if selectedIdentityIDs.count == 1, let id = selectedIdentityIDs.first {
                activeIdentity = identities.first { $0.id == id }
            } else {
                activeIdentity = nil
            }
        }
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
        HStack {
            Text("Identities")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadIdentities(force: true)
            }

            Spacer()

            Button { showVerifySheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadIdentities(force: true)
            }

            Button {
                identitiesToDelete = identities.filter { selectedIdentityIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(identityDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(identityDeleteDisabled)
            .help(selectedIdentityIDs.count <= 1 ? "Delete Identity" : "Delete \(selectedIdentityIDs.count) Identities")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var identityListContent: some View {
        if isLoading && identities.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading identities...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, identities.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadIdentities(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if identities.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No identities")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Verify Identity") {
                    showVerifySheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if identities.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter identities")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredIdentities, selection: $selectedIdentityIDs) { identity in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Verify Identity") {
                        showVerifySheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(identities.count) identit\(identities.count == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedIdentityIDs.count > 1 {
                        Text("(\(selectedIdentityIDs.count) selected)")
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

    private func typeBadge(for identity: SESIdentity) -> some View {
        Text(identity.typeBadge)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(identity.isEmail ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(identity.isEmail ? .blue : .purple)
    }

    private var verifiedBadge: some View {
        Text("Verified")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
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

    private func loadIdentities(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listIdentities()
                let sorted = loaded.sorted { $0.identity.localizedStandardCompare($1.identity) == .orderedAscending }
                if identities != sorted {
                    identities = sorted
                }
                if !hasRestoredSession, let savedName = restoreIdentityName,
                   let identity = identities.first(where: { $0.identity == savedName }) {
                    selectedIdentityIDs = [identity.id]
                    activeIdentity = identity
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

    private func deleteIdentities(_ targets: [SESIdentity]) {
        Task {
            var deletedIDs: Set<SESIdentity.ID> = []
            for identity in targets {
                do {
                    try await service.deleteIdentity(identity: identity.identity)
                    deletedIDs.insert(identity.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedIdentityIDs.subtract(deletedIDs)
                if let active = activeIdentity, deletedIDs.contains(active.id) {
                    activeIdentity = nil
                }
                loadIdentities(force: true)
            }
        }
    }
}
