import SwiftUI
import AppKit

struct ACMCertificateListView: View {
    @ObservedObject var service: ACMService
    @ObservedObject var toolbarState: ACMToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedCertIDs: Set<ACMCertificateSummary.ID>
    @Binding var activeCertificate: ACMCertificateSummary?
    var restoreCertArn: String?

    @State private var certificates: [ACMCertificateSummary] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRequestSheet = false
    @State private var showImportSheet = false
    @State private var certsToDelete: [ACMCertificateSummary] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            certListHeader
            Divider()
            certListContent
        }
        .sheet(isPresented: $showRequestSheet) {
            ACMRequestCertificateView(service: service)
                .onDisappear { loadCertificates(force: true) }
        }
        .sheet(isPresented: $showImportSheet) {
            ACMImportCertificateView(service: service)
                .onDisappear { loadCertificates(force: true) }
        }
        .alert(
            certsToDelete.count == 1
                ? "Delete Certificate"
                : "Delete \(certsToDelete.count) Certificates",
            isPresented: Binding(
                get: { !certsToDelete.isEmpty },
                set: { if !$0 { certsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteCertificates(certsToDelete)
            }
            Button("Cancel", role: .cancel) {
                certsToDelete = []
            }
        } message: {
            if certsToDelete.count == 1, let cert = certsToDelete.first {
                Text("Are you sure you want to delete the certificate for \"\(cert.displayDomain)\"?")
            } else {
                Text("Are you sure you want to delete \(certsToDelete.count) certificates?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadCertificates() }
        .onAutoRefresh(canRefresh: { !showRequestSheet && !showImportSheet && certsToDelete.isEmpty && !isLoading }) {
            loadCertificates(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedCertIDs = []
            activeCertificate = nil
            certificates = []
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
        HStack {
            Text("Certificates")
                .font(.headline)
                .lineLimit(1)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadCertificates(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showRequestSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadCertificates(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: certDeleteDisabled, help: selectedCertIDs.count <= 1 ? "Delete Certificate" : "Delete \(selectedCertIDs.count) Certificates") {
                certsToDelete = certificates.filter { selectedCertIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var certListContent: some View {
        if isLoading && certificates.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading certificates...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, certificates.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadCertificates(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if certificates.isEmpty {
            EmptyStateView(icon: "checkmark.seal", message: "No certificates")
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
        } else {
            VStack(spacing: 0) {
                if certificates.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter certificates")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredCertificates, selection: $selectedCertIDs) { cert in
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
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

                // Status bar
                Divider()
                HStack {
                    Text("\(certificates.count) certificate\(certificates.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedCertIDs.count > 1 {
                        Text("(\(selectedCertIDs.count) selected)")
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
                let loaded = try await service.listCertificates()
                let freshCerts = loaded.sorted { $0.domainName.localizedStandardCompare($1.domainName) == .orderedAscending }
                if certificates != freshCerts {
                    certificates = freshCerts
                }
                if !hasRestoredSession, let savedArn = restoreCertArn,
                   let cert = certificates.first(where: { $0.certificateArn == savedArn }) {
                    selectedCertIDs = [cert.id]
                    activeCertificate = cert
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

    private func deleteCertificates(_ targets: [ACMCertificateSummary]) {
        Task {
            var deletedIDs: Set<ACMCertificateSummary.ID> = []
            for cert in targets {
                do {
                    try await service.deleteCertificate(arn: cert.certificateArn)
                    deletedIDs.insert(cert.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedCertIDs.subtract(deletedIDs)
                if let active = activeCertificate, deletedIDs.contains(active.id) {
                    activeCertificate = nil
                }
                loadCertificates(force: true)
            }
        }
    }
}
