import SwiftUI
import AppKit

struct SupportCaseListView: View {
    @ObservedObject var service: SupportService
    @ObservedObject var toolbarState: SupportToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedCaseIDs: Set<SupportCase.ID>
    @Binding var activeCase: SupportCase?
    var restoreCaseId: String?

    @State private var cases: [SupportCase] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var caseToResolve: SupportCase?
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""
    @State private var showResolved = false

    var body: some View {
        VStack(spacing: 0) {
            caseListHeader
            Divider()
            mockBanner
            Divider()
            caseListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SupportCreateCaseView(service: service)
                .onDisappear { loadCases(force: true) }
        }
        .alert(
            "Resolve Case",
            isPresented: Binding(
                get: { caseToResolve != nil },
                set: { if !$0 { caseToResolve = nil } }
            )
        ) {
            Button("Resolve", role: .destructive) {
                if let c = caseToResolve {
                    resolveCase(c)
                }
            }
            Button("Cancel", role: .cancel) {
                caseToResolve = nil
            }
        } message: {
            if let c = caseToResolve {
                Text("Are you sure you want to resolve case \"\(c.subject)\"?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadCases() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && caseToResolve == nil && !isLoading }) {
            loadCases(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedCaseIDs = []
            activeCase = nil
            cases = []
            loadCases(force: true)
        }
        .onChange(of: selectedCaseIDs) {
            if selectedCaseIDs.count == 1, let id = selectedCaseIDs.first {
                activeCase = cases.first { $0.id == id }
            } else {
                activeCase = nil
            }
        }
        .onChange(of: showResolved) {
            loadCases(force: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .create:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .resolve:
                toolbarState.pendingAction = nil
                if let active = activeCase {
                    caseToResolve = active
                }
            }
        }
    }

    private var filteredCases: [SupportCase] {
        guard !searchText.isEmpty else { return cases }
        let query = searchText.lowercased()
        return cases.filter {
            $0.subject.lowercased().contains(query) ||
            $0.caseId.lowercased().contains(query) ||
            $0.displayId.lowercased().contains(query)
        }
    }

    private var mockBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("Mock API — cases may not persist across restarts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.06))
    }

    // MARK: - Header

    private var caseListHeader: some View {
        HStack {
            Text("Cases")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadCases(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadCases(force: true)
            }

            Toggle(isOn: $showResolved) {
                Image(systemName: "checkmark.circle")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help(showResolved ? "Hide resolved cases" : "Show resolved cases")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var caseListContent: some View {
        if isLoading && cases.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading cases...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, cases.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadCases(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if cases.isEmpty {
            EmptyStateView(icon: "lifepreserver", message: "No cases")
            .contextMenu {
                Button("Create Case") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if cases.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter cases")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredCases, selection: $selectedCaseIDs) { supportCase in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(supportCase.subject)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if !supportCase.displayId.isEmpty {
                                Text(supportCase.displayId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            statusBadge(supportCase)
                            severityBadge(supportCase)
                        }
                    }
                    .tag(supportCase.id)
                    .contextMenu {
                        Button("Copy Case ID") { copyToClipboard(supportCase.caseId) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Case") {
                                copyToClipboard(supportCase.describeCaseCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Cases") {
                                copyToClipboard(SupportCase.listCasesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Resolve Case") {
                                copyToClipboard(supportCase.resolveCaseCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Case") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Resolve") {
                            caseToResolve = supportCase
                        }
                        .disabled(appState.isReadOnly || supportCase.status.lowercased() == "resolved")
                    }
                }
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Create Case") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(cases.count) case\(cases.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func statusBadge(_ supportCase: SupportCase) -> some View {
        StatusBadge(text: supportCase.statusDisplayName, color: supportCase.statusBadgeColor)
    }

    private func severityBadge(_ supportCase: SupportCase) -> some View {
        Group {
            if !supportCase.severityCode.isEmpty {
                StatusBadge(text: supportCase.severityCode.capitalized, color: supportCase.severityBadgeColor)
            }
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

    private func loadCases(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.describeCases(includeResolved: showResolved)
                let freshCases = loaded.sorted {
                    let cmp = $0.subject.localizedStandardCompare($1.subject)
                    return cmp == .orderedAscending || (cmp == .orderedSame && $0.caseId < $1.caseId)
                }
                // Only update if the case IDs or statuses changed — LocalStack's
                // mock can return subtly different field values on each call.
                let oldSnapshot = cases.map { "\($0.caseId)|\($0.status)" }
                let newSnapshot = freshCases.map { "\($0.caseId)|\($0.status)" }
                if oldSnapshot != newSnapshot {
                    cases = freshCases
                }
                if !hasRestoredSession, let savedId = restoreCaseId,
                   let restored = cases.first(where: { $0.caseId == savedId }) {
                    selectedCaseIDs = [restored.id]
                    activeCase = restored
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

    private func resolveCase(_ target: SupportCase) {
        Task {
            do {
                try await service.resolveCase(caseId: target.caseId)
                loadCases(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
