import SwiftUI
import AppKit

struct OpenSearchDomainListView: View {
    @ObservedObject var service: OpenSearchService
    @ObservedObject var toolbarState: OpenSearchToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedDomainIDs: Set<OpenSearchDomain.ID>
    @Binding var activeDomain: OpenSearchDomain?
    var restoreDomainName: String?

    @State private var showCreateSheet = false
    @State private var domainsToDelete: [OpenSearchDomain] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?
    @StateObject private var loader = ListLoader<OpenSearchDomain>()
    private var domains: [OpenSearchDomain] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            domainListHeader
            Divider()
            domainListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            OpenSearchCreateDomainView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadDomains(force: true) }
        }
        .deleteConfirmation(items: $domainsToDelete, noun: "Domain") { items in
            if items.count == 1, let domain = items.first {
                Text("Are you sure you want to delete domain \"\(domain.domainName)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) domains?")
            }
        } onDelete: { deleteDomains($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadDomains() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && domainsToDelete.isEmpty && !loader.isLoading }) {
            loadDomains(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedDomainIDs = []
            activeDomain = nil
            loader.items = []
            loadDomains(force: true)
        }
        .syncSelection(selectedDomainIDs, items: domains, activeItem: $activeDomain)
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
        ListHeaderBar(
            title: "Domains",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: domainDeleteDisabled,
            deleteHelp: selectedDomainIDs.count <= 1 ? "Delete Domain" : "Delete \(selectedDomainIDs.count) Domains",
            onRefresh: { loadDomains(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { domainsToDelete = domains.filter { selectedDomainIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var domainListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: domains.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading domains...", emptyIcon: "magnifyingglass.circle", emptyMessage: "No domains", onRetry: { loadDomains(force: true) }) {
            VStack(spacing: 0) {
                if domains.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter domains")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedDomainIDs) {
                    ForEach(filteredDomains) { domain in
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
                    .selectionForeground()
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
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Domain") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: domains.count, selectedCount: selectedDomainIDs.count, noun: "domain")
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

    // MARK: - Data

    private func loadDomains(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listDomains() },
            sort: { $0.domainName.localizedStandardCompare($1.domainName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreDomainName,
               let domain = items.first(where: { $0.domainName == savedName }) {
                selectedDomainIDs = [domain.id]
                activeDomain = domain
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let domain = items.first(where: { $0.domainName == name }) {
                selectedDomainIDs = [domain.id]
                activeDomain = domain
                pendingSelectName = nil
            }
        }
    }

    private func deleteDomains(_ targets: [OpenSearchDomain]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteDomain(name: $0.domainName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .opensearch, by: deleted.count)
                selectedDomainIDs.subtract(deleted)
                if let active = activeDomain, deleted.contains(active.id) {
                    activeDomain = nil
                }
                loadDomains(force: true)
            }
        }
    }

}
