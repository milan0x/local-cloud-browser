import SwiftUI
import AppKit

struct SupportCaseListView: View {
    @ObservedObject var service: SupportService
    @ObservedObject var toolbarState: SupportToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedCaseIDs: Set<SupportCase.ID>
    @Binding var activeCase: SupportCase?
    var restoreCaseId: String?

    @StateObject private var loader = ListLoader<SupportCase>()
    private var cases: [SupportCase] { loader.items }
    @State private var showCreateSheet = false
    @State private var caseToResolve: SupportCase?
    @State private var serviceError: ServiceError?
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
        .onAutoRefresh(canRefresh: { !showCreateSheet && caseToResolve == nil && !loader.isLoading }) {
            loadCases(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedCaseIDs = []
            activeCase = nil
            loader.items = []
            loadCases(force: true)
        }
        .syncSelection(selectedCaseIDs, items: cases, activeItem: $activeCase)
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
        ListHeaderBar(
            title: "Cases",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            onRefresh: { loadCases(force: true) },
            onCreate: { showCreateSheet = true }
        ) {
            Toggle(isOn: $showResolved) {
                Image(systemName: "checkmark.circle")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help(showResolved ? "Hide resolved cases" : "Show resolved cases")
        }
    }

    // MARK: - Content

    private var caseListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: cases.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading cases...", onRetry: { loadCases(force: true) }) {
            if cases.isEmpty {
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
                        .foregroundStyle(selectedCaseIDs.contains(supportCase.id) ? Color.white : Color.primary)
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
                        if loader.errorMessage != nil {
                            ConnectionLostBanner()
                        }
                    }
                    .contextMenu {
                        Button("Create Case") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                    }

                    ListStatusBar(totalCount: cases.count, selectedCount: selectedCaseIDs.count, noun: "case")
                }
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

    // MARK: - Data

    private func loadCases(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.describeCases(includeResolved: showResolved) },
            sort: {
                let cmp = $0.subject.localizedStandardCompare($1.subject)
                return cmp == .orderedAscending || (cmp == .orderedSame && $0.caseId < $1.caseId)
            }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedId = restoreCaseId,
               let restored = items.first(where: { $0.caseId == savedId }) {
                selectedCaseIDs = [restored.id]
                activeCase = restored
            }
            loader.hasRestoredSession = true
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
