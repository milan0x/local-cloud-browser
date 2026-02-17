import SwiftUI
import AppKit

struct ACMCertificateListView: View {
    @ObservedObject var service: ACMService
    @ObservedObject var toolbarState: ACMToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedCertIDs: Set<ACMCertificateSummary.ID>
    @Binding var activeCertificate: ACMCertificateSummary?
    var restoreCertArn: String?

    @State private var showRequestSheet = false
    @State private var showImportSheet = false
    @State private var certsToDelete: [ACMCertificateSummary] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @StateObject private var regionLoader = FavoriteRegionLoader<ACMCertificateSummary>()
    @StateObject private var loader = ListLoader<ACMCertificateSummary>()
    private var certificates: [ACMCertificateSummary] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            certListHeader
            Divider()
            certListContent
            AddFavoriteRegionButton(currentRegion: appState.region)
        }
        .sheet(isPresented: $showRequestSheet) {
            ACMRequestCertificateView(service: service)
                .onDisappear { loadCertificates(force: true) }
        }
        .sheet(isPresented: $showImportSheet) {
            ACMImportCertificateView(service: service)
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
        .favoriteRegionSupport(regionLoader: regionLoader) { [service] in try await service.listCertificates(region: $0) }
        .onAutoRefresh(canRefresh: { !showRequestSheet && !showImportSheet && certsToDelete.isEmpty && !loader.isLoading }) {
            loadCertificates(force: true, silent: true)
            regionLoader.loadAllExpanded(silent: true)
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
            deleteDisabled: certDeleteDisabled,
            deleteHelp: selectedCertIDs.count <= 1 ? "Delete Certificate" : "Delete \(selectedCertIDs.count) Certificates",
            onRefresh: { loadCertificates(force: true) },
            onCreate: { showRequestSheet = true },
            onDelete: { certsToDelete = certificates.filter { selectedCertIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var certListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: certificates.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading certificates...", onRetry: { loadCertificates(force: true) }) {
            VStack(spacing: 0) {
                if certificates.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter certificates")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedCertIDs) {
                    if certificates.isEmpty {
                        EmptyStateView(icon: "checkmark.seal", message: "No certificates")
                            .listRowSeparator(.hidden)
                    }
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
                            Button("Delete (\(selected.count) Certificates)", role: .destructive) {
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
                    FavoriteRegionSections(loader: regionLoader, currentRegion: appState.region,
                        selectBy: \.certificateArn
                    ) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayDomain)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(item.truncatedArn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            statusBadge(item.status)
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

                ListStatusBar(totalCount: certificates.count, selectedCount: selectedCertIDs.count, noun: "certificate")
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
            fetch: { [service] in try await service.listCertificates() },
            sort: { $0.domainName.localizedStandardCompare($1.domainName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedArn = restoreCertArn,
               let cert = items.first(where: { $0.certificateArn == savedArn }) {
                selectedCertIDs = [cert.id]
                activeCertificate = cert
            }
            loader.hasRestoredSession = true
            if let item = regionLoader.consumePendingSelection(from: items, by: \.certificateArn) {
                selectedCertIDs = [item.id]
                activeCertificate = item
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
                selectedCertIDs.subtract(deleted)
                if let active = activeCertificate, deleted.contains(active.id) { activeCertificate = nil }
                loadCertificates(force: true)
            }
        }
    }
}
