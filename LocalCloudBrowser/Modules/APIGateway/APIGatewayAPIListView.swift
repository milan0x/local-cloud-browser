import SwiftUI
import AppKit

struct APIGatewayAPIListView: View {
    @ObservedObject var service: APIGatewayService
    @ObservedObject var toolbarState: APIGatewayToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedAPIIDs: Set<RestApi.ID>
    @Binding var activeAPI: RestApi?
    var restoreAPIId: String?

    @StateObject private var loader = ListLoader<RestApi>()
    private var apis: [RestApi] { loader.items }
    @State private var pendingSelectName: String?
    @State private var showCreateSheet = false
    @State private var apisToDelete: [RestApi] = []
    @State private var serviceError: ServiceError?
    @State private var apiToShowDetail: RestApi?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            apiListHeader
            Divider()
            apiListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            APIGatewayCreateAPIView(service: service, existingAPINames: Set(apis.map(\.name))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadAPIs(force: true) }
        }
        .alert(
            apisToDelete.count == 1
                ? "Delete REST API"
                : "Delete \(apisToDelete.count) REST APIs",
            isPresented: Binding(
                get: { !apisToDelete.isEmpty },
                set: { if !$0 { apisToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteAPIs(apisToDelete)
            }
            Button("Cancel", role: .cancel) {
                apisToDelete = []
            }
        } message: {
            if apisToDelete.count == 1, let api = apisToDelete.first {
                Text("Are you sure you want to delete \"\(api.name)\"?\n\nAll resources, deployments, and stages will be deleted.")
            } else {
                let names = apisToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these APIs?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $apiToShowDetail) { api in
            APIGatewayAPIDetailView(api: api, endpoint: appState.endpoint)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadAPIs() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && apisToDelete.isEmpty && apiToShowDetail == nil && !loader.isLoading }) {
            loadAPIs(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedAPIIDs = []
            activeAPI = nil
            loader.items = []
            loadAPIs(force: true)
        }
        .syncSelection(selectedAPIIDs, items: apis, activeItem: $activeAPI)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeAPI {
                    apisToDelete = [active]
                }
            default:
                break // handled by browser view
            }
        }
    }

    private var apiDeleteDisabled: Bool {
        appState.isReadOnly || selectedAPIIDs.isEmpty
    }

    private var filteredAPIs: [RestApi] {
        guard !searchText.isEmpty else { return apis }
        let query = searchText.lowercased()
        return apis.filter { $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query) }
    }

    // MARK: - Header

    private var apiListHeader: some View {
        ListHeaderBar(
            title: "REST APIs",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: apis.count,
            deleteDisabled: apiDeleteDisabled,
            deleteHelp: selectedAPIIDs.count <= 1 ? "Delete API" : "Delete \(selectedAPIIDs.count) APIs",
            onRefresh: { loadAPIs(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { apisToDelete = apis.filter { selectedAPIIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var apiListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: apis.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading REST APIs...", emptyIcon: "network", emptyMessage: "No REST APIs", onRetry: { loadAPIs(force: true) }) {
            VStack(spacing: 0) {
                if apis.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter APIs")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedAPIIDs) {
                    ForEach(filteredAPIs) { api in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(api.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            StatusBadge(text: api.endpointType, color: .blue)
                            Text(api.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .selectionForeground()
                    .tag(api.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(api.name) }
                        Button("Copy ID") { copyToClipboard(api.id) }
                        Menu("Copy as AWS CLI") {
                            Button("Get REST API") {
                                copyToClipboard(api.getRestApiCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Get Resources") {
                                copyToClipboard(api.getResourcesCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List REST APIs") {
                                copyToClipboard(RestApi.listRestApisCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("View Details") {
                            apiToShowDetail = api
                        }
                        Divider()
                        Button("Create REST API") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedAPIIDs.count > 1 && selectedAPIIDs.contains(api.id) {
                            let selected = apis.filter { selectedAPIIDs.contains($0.id) }
                            Button("Delete \(selected.count) APIs", role: .destructive) {
                                apisToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                apisToDelete = [api]
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
                    Button("Create REST API") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedAPIIDs.count == 1,
                       let id = selectedAPIIDs.first,
                       let api = apis.first(where: { $0.id == id }) {
                        apiToShowDetail = api
                    }
                })

                ListStatusBar(totalCount: apis.count, selectedCount: selectedAPIIDs.count, noun: "API")
            }
        }
    }

    // MARK: - Data

    private func loadAPIs(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listRestApis() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedId = restoreAPIId,
               let api = items.first(where: { $0.id == savedId }) {
                selectedAPIIDs = [api.id]
                activeAPI = api
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let api = items.first(where: { $0.name == name }) {
                selectedAPIIDs = [api.id]
                activeAPI = api
                pendingSelectName = nil
            }
        }
    }

    private func deleteAPIs(_ targets: [RestApi]) {
        Task {
            selectedAPIIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<RestApi.ID> = []
            for api in targets {
                do {
                    try await service.deleteRestApi(id: api.id)
                    deletedIDs.insert(api.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedAPIIDs.subtract(deletedIDs)
                if let active = activeAPI, deletedIDs.contains(active.id) {
                    activeAPI = nil
                }
                loadAPIs(force: true)
            }
        }
    }
}
