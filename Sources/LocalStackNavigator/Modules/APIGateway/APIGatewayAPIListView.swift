import SwiftUI
import AppKit

struct APIGatewayAPIListView: View {
    @ObservedObject var service: APIGatewayService
    @ObservedObject var toolbarState: APIGatewayToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedAPIIDs: Set<RestApi.ID>
    @Binding var activeAPI: RestApi?
    var restoreAPIId: String?

    @State private var apis: [RestApi] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var apisToDelete: [RestApi] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var apiToShowDetail: RestApi?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            apiListHeader
            Divider()
            apiListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            APIGatewayCreateAPIView(service: service, existingAPINames: Set(apis.map(\.name)))
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
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && apisToDelete.isEmpty && apiToShowDetail == nil && !isLoading else { return }
            loadAPIs(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedAPIIDs = []
            activeAPI = nil
            apis = []
            loadAPIs(force: true)
        }
        .onChange(of: appState.region) {
            selectedAPIIDs = []
            activeAPI = nil
            apis = []
            loadAPIs(force: true)
        }
        .onChange(of: selectedAPIIDs) {
            if selectedAPIIDs.count == 1, let id = selectedAPIIDs.first {
                activeAPI = apis.first { $0.id == id }
            } else {
                activeAPI = nil
            }
        }
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
        HStack {
            Text("REST APIs")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadAPIs(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadAPIs(force: true)
            }

            Button {
                apisToDelete = apis.filter { selectedAPIIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(apiDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(apiDeleteDisabled)
            .help(selectedAPIIDs.count <= 1 ? "Delete API" : "Delete \(selectedAPIIDs.count) APIs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var apiListContent: some View {
        if isLoading && apis.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading REST APIs...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, apis.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadAPIs(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apis.isEmpty {
            EmptyStateView(icon: "network", message: "No REST APIs")
            .contextMenu {
                Button("Create REST API") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if apis.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter APIs")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredAPIs, selection: $selectedAPIIDs) { api in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(api.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(api.endpointType)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                            Text(api.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(api.id)
                    .contextMenu {
                        Button("View Details") {
                            apiToShowDetail = api
                        }
                        Divider()
                        Button("Copy ID") { copyToClipboard(api.id) }
                        Button("Copy Name") { copyToClipboard(api.name) }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
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

                // Status bar
                Divider()
                HStack {
                    Text("\(apis.count) API\(apis.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedAPIIDs.count > 1 {
                        Text("(\(selectedAPIIDs.count) selected)")
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

    private func loadAPIs(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listRestApis()
                let freshAPIs = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if apis != freshAPIs {
                    apis = freshAPIs
                }
                if !hasRestoredSession, let savedId = restoreAPIId,
                   let api = apis.first(where: { $0.id == savedId }) {
                    selectedAPIIDs = [api.id]
                    activeAPI = api
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

    private func deleteAPIs(_ targets: [RestApi]) {
        Task {
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
