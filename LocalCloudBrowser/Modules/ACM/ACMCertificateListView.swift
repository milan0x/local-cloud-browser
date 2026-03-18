import SwiftUI
import AppKit

struct ACMCertificateListView: View {
    @ObservedObject var service: ACMService
    @ObservedObject var toolbarState: ACMToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedCertIDs: Set<ACMCertificateSummary.ID>
    @Binding var activeCertificate: ACMCertificateSummary?
    var restoreCertArn: String?

    @State private var pendingSelectName: String?
    @State private var showRequestSheet = false
    @State private var showImportSheet = false
    @State private var certsToDelete: [ACMCertificateSummary] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @StateObject private var loader = PaginatedListLoader<ACMCertificateSummary>()
    private var certificates: [ACMCertificateSummary] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            certListHeader
            Divider()
            certListContent
        }
        .sheet(isPresented: $showRequestSheet) {
            ACMRequestCertificateView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadCertificates(force: true) }
        }
        .sheet(isPresented: $showImportSheet) {
            ACMImportCertificateView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadCertificates(force: true) }
        }
        .deleteConfirmation(items: $certsToDelete, noun: "Certificate") { items in
            if items.count == 1, let cert = items.first {
                Text("Are you sure you want to delete the certificate for \"\(cert.displayDomain)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) certificates?")
            }
        } onDelete: { deleteCertificates($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadCertificates() }
        .onAutoRefresh(canRefresh: { !showRequestSheet && !showImportSheet && certsToDelete.isEmpty && !loader.isLoading }) {
            loadCertificates(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedCertIDs = []
            activeCertificate = nil
            loader.items = []
            loadCertificates(force: true)
        }
        .syncSelection(selectedCertIDs, items: certificates, activeItem: $activeCertificate)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .requestCertificate:
                toolbarState.pendingAction = nil
                showRequestSheet = true
            case .importCertificate:
                toolbarState.pendingAction = nil
                showImportSheet = true
            case .deleteCertificate:
                toolbarState.pendingAction = nil
                if let active = activeCertificate {
                    certsToDelete = [active]
                }
            }
        }
    }

    private var certDeleteDisabled: Bool {
        appState.isReadOnly || selectedCertIDs.isEmpty
    }

    private var filteredCertificates: [ACMCertificateSummary] {
        guard !searchText.isEmpty else { return certificates }
        let query = searchText.lowercased()
        return certificates.filter {
            $0.domainName.lowercased().contains(query) ||
            $0.certificateArn.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var certListHeader: some View {
        ListHeaderBar(
            title: "Certificates",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: certificates.count,
            deleteDisabled: certDeleteDisabled,
            deleteHelp: selectedCertIDs.count <= 1 ? "Delete Certificate" : "Delete \(selectedCertIDs.count) Certificates",
            onRefresh: { loadCertificates(force: true) },
            onCreate: { showRequestSheet = true },
            onDelete: { certsToDelete = certificates.filter { selectedCertIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var certListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: certificates.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading certificates...", emptyIcon: "checkmark.seal", emptyMessage: "No certificates", onRetry: { loadCertificates(force: true) }) {
            VStack(spacing: 0) {
                if certificates.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter certificates")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedCertIDs) {
                    ForEach(filteredCertificates) { cert in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cert.displayDomain)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(cert.truncatedArn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            statusBadge(cert.status)
                            typeBadge(cert.type)
                        }
                    }
                    .selectionForeground()
                    .tag(cert.id)
                    .contextMenu {
                        Button("Copy ARN") { copyToClipboard(cert.certificateArn) }
                        Button("Copy Domain") { copyToClipboard(cert.domainName) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Certificate") {
                                copyToClipboard(cert.describeCertificateCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Certificates") {
                                copyToClipboard(ACMCertificateSummary.listCertificatesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Delete Certificate") {
                                copyToClipboard(cert.deleteCertificateCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Request Certificate") {
                            showRequestSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Button("Import Certificate") {
                            showImportSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedCertIDs.count > 1 && selectedCertIDs.contains(cert.id) {
                            let selected = certificates.filter { selectedCertIDs.contains($0.id) }
                            Button("Delete \(selected.count) Certificates", role: .destructive) {
                                certsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                certsToDelete = [cert]
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
                    Button("Request Certificate") {
                        showRequestSheet = true
                    }
                    .disabled(appState.isReadOnly)
                    Button("Import Certificate") {
                        showImportSheet = true
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

                if filteredCertificates.isEmpty && !searchText.isEmpty && loader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            loader.searchAll { $0.domainName.lowercased().contains(query) }
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

                ListStatusBar(totalCount: certificates.count, selectedCount: selectedCertIDs.count, noun: "certificate", hasMorePages: loader.hasMorePages)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let display = status.replacingOccurrences(of: "_", with: " ")
        return StatusBadge(text: display, color: statusColor(status))
    }

    private func typeBadge(_ type: String) -> some View {
        let display = type == "AMAZON_ISSUED" ? "Amazon" : (type == "IMPORTED" ? "Imported" : type)
        let color: Color = type == "IMPORTED" ? .purple : .blue
        return StatusBadge(text: display, color: color)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ISSUED": .green
        case "PENDING_VALIDATION": .orange
        case "EXPIRED", "FAILED", "REVOKED": .red
        case "INACTIVE": .gray
        default: .gray
        }
    }

    // MARK: - Data

    private func loadCertificates(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listCertificatesPage(token: token) },
            sort: { $0.domainName.localizedStandardCompare($1.domainName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedArn = restoreCertArn,
               let cert = items.first(where: { $0.certificateArn == savedArn }) {
                selectedCertIDs = [cert.id]
                activeCertificate = cert
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let cert = items.first(where: { $0.domainName == name || $0.certificateArn == name }) {
                selectedCertIDs = [cert.id]
                activeCertificate = cert
                pendingSelectName = nil
            }
        }
    }

    private func deleteCertificates(_ targets: [ACMCertificateSummary]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteCertificate(arn: $0.certificateArn)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .acm, by: deleted.count)
                selectedCertIDs.subtract(deleted)
                if let active = activeCertificate, deleted.contains(active.id) { activeCertificate = nil }
                loadCertificates(force: true)
            }
        }
    }
}
