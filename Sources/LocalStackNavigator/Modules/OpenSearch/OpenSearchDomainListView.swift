import SwiftUI
import AppKit

struct OpenSearchDomainListView: View {
    @ObservedObject var service: OpenSearchService
    @ObservedObject var toolbarState: OpenSearchToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedDomainIDs: Set<OpenSearchDomain.ID>
    @Binding var activeDomain: OpenSearchDomain?
    var restoreDomainName: String?

    @State private var domains: [OpenSearchDomain] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var domainsToDelete: [OpenSearchDomain] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            domainListHeader
            Divider()
            domainListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            OpenSearchCreateDomainView(service: service)
                .onDisappear { loadDomains(force: true) }
        }
        .alert(
            domainsToDelete.count == 1
                ? "Delete Domain"
                : "Delete \(domainsToDelete.count) Domains",
            isPresented: Binding(
                get: { !domainsToDelete.isEmpty },
                set: { if !$0 { domainsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteDomains(domainsToDelete)
            }
            Button("Cancel", role: .cancel) {
                domainsToDelete = []
            }
        } message: {
            if domainsToDelete.count == 1, let domain = domainsToDelete.first {
                Text("Are you sure you want to delete domain \"\(domain.domainName)\"?")
            } else {
                Text("Are you sure you want to delete \(domainsToDelete.count) domains?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadDomains() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && domainsToDelete.isEmpty && !isLoading }) {
            loadDomains(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedDomainIDs = []
            activeDomain = nil
            domains = []
            loadDomains(force: true)
        }
        .onChange(of: selectedDomainIDs) {
            if selectedDomainIDs.count == 1, let id = selectedDomainIDs.first {
                activeDomain = domains.first { $0.id == id }
            } else {
                activeDomain = nil
            }
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createDomain:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteDomain:
                toolbarState.pendingAction = nil
                if let active = activeDomain {
                    domainsToDelete = [active]
                }
            }
        }
    }

    private var domainDeleteDisabled: Bool {
        appState.isReadOnly || selectedDomainIDs.isEmpty
    }

    private var filteredDomains: [OpenSearchDomain] {
        guard !searchText.isEmpty else { return domains }
        let query = searchText.lowercased()
        return domains.filter {
            $0.domainName.lowercased().contains(query) ||
            $0.engineVersion.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var domainListHeader: some View {
        HStack {
            Text("Domains")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadDomains(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadDomains(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: domainDeleteDisabled, help: selectedDomainIDs.count <= 1 ? "Delete Domain" : "Delete \(selectedDomainIDs.count) Domains") {
                domainsToDelete = domains.filter { selectedDomainIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var domainListContent: some View {
        if isLoading && domains.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading domains...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, domains.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadDomains(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if domains.isEmpty {
            EmptyStateView(icon: "magnifyingglass.circle", message: "No domains")
            .contextMenu {
                Button("Create Domain") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if domains.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter domains")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredDomains, selection: $selectedDomainIDs) { domain in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(domain.domainName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(domain.engineDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        statusBadge(for: domain)
                    }
                    .tag(domain.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(domain.domainName) }
                        if !domain.arn.isEmpty {
                            Button("Copy ARN") { copyToClipboard(domain.arn) }
                        }
                        if !domain.endpoint.isEmpty {
                            Button("Copy Endpoint") { copyToClipboard(domain.endpoint) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Domain") {
                                copyToClipboard(domain.describeDomainCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Domains") {
                                copyToClipboard(OpenSearchDomain.listDomainsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Domain") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedDomainIDs.count > 1 && selectedDomainIDs.contains(domain.id) {
                            let selected = domains.filter { selectedDomainIDs.contains($0.id) }
                            Button("Delete (\(selected.count) Domains)", role: .destructive) {
                                domainsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                domainsToDelete = [domain]
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
                    Button("Create Domain") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(domains.count) domain\(domains.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedDomainIDs.count > 1 {
                        Text("(\(selectedDomainIDs.count) selected)")
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

    private func statusBadge(for domain: OpenSearchDomain) -> some View {
        StatusBadge(text: domain.status, color: statusColor(domain.status))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Active": .green
        case "Processing": .blue
        case "Deleting": .red
        default: .gray
        }
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

    private func loadDomains(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listDomains()
                let freshDomains = loaded.sorted { $0.domainName.localizedStandardCompare($1.domainName) == .orderedAscending }
                if domains != freshDomains {
                    domains = freshDomains
                }
                if !hasRestoredSession, let savedName = restoreDomainName,
                   let domain = domains.first(where: { $0.domainName == savedName }) {
                    selectedDomainIDs = [domain.id]
                    activeDomain = domain
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

    private func deleteDomains(_ targets: [OpenSearchDomain]) {
        Task {
            var deletedIDs: Set<OpenSearchDomain.ID> = []
            for domain in targets {
                do {
                    try await service.deleteDomain(name: domain.domainName)
                    deletedIDs.insert(domain.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedDomainIDs.subtract(deletedIDs)
                if let active = activeDomain, deletedIDs.contains(active.id) {
                    activeDomain = nil
                }
                loadDomains(force: true)
            }
        }
    }
}
