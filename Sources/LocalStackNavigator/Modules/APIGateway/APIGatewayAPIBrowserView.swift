import SwiftUI
import AppKit

struct APIGatewayAPIBrowserView: View {
    @ObservedObject var service: APIGatewayService
    let api: RestApi
    @ObservedObject var toolbarState: APIGatewayToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var selectedTab: BrowserTab = .resources
    @State private var resources: [APIResource] = []
    @State private var deployments: [APIDeployment] = []
    @State private var stages: [APIStage] = []
    @State private var isLoadingResources = false
    @State private var isLoadingDeployments = false
    @State private var isLoadingStages = false
    @State private var serviceError: ServiceError?

    // Resource detail
    @State private var selectedResourceId: String?
    @State private var selectedResourceMethods: [APIMethod] = []
    @State private var isLoadingMethods = false

    // Sheets
    @State private var showDetailSheet = false
    @State private var showCreateResourceSheet = false
    @State private var showCreateMethodSheet = false
    @State private var showCreateDeploymentSheet = false
    @State private var showCreateStageSheet = false

    // Delete confirmations
    @State private var resourceToDelete: APIResource?
    @State private var stageToDelete: APIStage?
    @State private var methodToDelete: String?

    enum BrowserTab: String, CaseIterable {
        case resources = "Resources"
        case stages = "Stages"
        case deployments = "Deployments"
    }

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider()

            SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 16, verticalPadding: 8)

            Divider()

            switch selectedTab {
            case .resources:
                resourcesTab
            case .stages:
                stagesTab
            case .deployments:
                deploymentsTab
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            APIGatewayAPIDetailView(api: api, endpoint: appState.endpoint)
        }
        .sheet(isPresented: $showCreateResourceSheet) {
            APIGatewayCreateResourceView(service: service, apiId: api.id, resources: resources)
                .onDisappear { loadResources() }
        }
        .sheet(isPresented: $showCreateMethodSheet) {
            if let resId = selectedResourceId,
               let resource = resources.first(where: { $0.id == resId }) {
                APIGatewayCreateMethodView(
                    service: service,
                    apiId: api.id,
                    resourceId: resId,
                    resourcePath: resource.path,
                    existingMethods: Set(selectedResourceMethods.map(\.httpMethod))
                )
                .onDisappear {
                    loadResources()
                    if let resId = selectedResourceId {
                        loadMethods(resourceId: resId)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateDeploymentSheet) {
            APIGatewayCreateDeploymentView(service: service, apiId: api.id)
                .onDisappear { loadDeployments() }
        }
        .sheet(isPresented: $showCreateStageSheet) {
            APIGatewayCreateStageView(service: service, apiId: api.id, deployments: deployments, existingStageNames: Set(stages.map(\.stageName)))
                .onDisappear { loadStages() }
        }
        .alert("Delete Resource", isPresented: Binding(
            get: { resourceToDelete != nil },
            set: { if !$0 { resourceToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let resource = resourceToDelete {
                    deleteResource(resource)
                }
            }
            Button("Cancel", role: .cancel) { resourceToDelete = nil }
        } message: {
            if let resource = resourceToDelete {
                Text("Are you sure you want to delete resource \"\(resource.path)\"?\n\nAll methods on this resource will also be deleted.")
            }
        }
        .alert("Delete Stage", isPresented: Binding(
            get: { stageToDelete != nil },
            set: { if !$0 { stageToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let stage = stageToDelete {
                    deleteStage(stage)
                }
            }
            Button("Cancel", role: .cancel) { stageToDelete = nil }
        } message: {
            if let stage = stageToDelete {
                Text("Are you sure you want to delete stage \"\(stage.stageName)\"?")
            }
        }
        .alert("Delete Method", isPresented: Binding(
            get: { methodToDelete != nil },
            set: { if !$0 { methodToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let method = methodToDelete, let resId = selectedResourceId {
                    deleteMethod(resourceId: resId, httpMethod: method)
                }
            }
            Button("Cancel", role: .cancel) { methodToDelete = nil }
        } message: {
            if let method = methodToDelete {
                Text("Are you sure you want to delete the \(method) method?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadAll() }
        .onChange(of: api) {
            resources = []
            deployments = []
            stages = []
            selectedResourceId = nil
            selectedResourceMethods = []
            loadAll()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showDetailSheet && !showCreateResourceSheet && !showCreateMethodSheet
                    && !showCreateDeploymentSheet && !showCreateStageSheet
                    && !isLoadingResources else { return }
            loadResources(silent: true)
            loadDeployments(silent: true)
            loadStages(silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .viewDetails:
                toolbarState.pendingAction = nil
                showDetailSheet = true
            case .createResource:
                toolbarState.pendingAction = nil
                showCreateResourceSheet = true
            case .addMethod:
                toolbarState.pendingAction = nil
                if selectedResourceId != nil {
                    showCreateMethodSheet = true
                }
            case .createDeployment:
                toolbarState.pendingAction = nil
                showCreateDeploymentSheet = true
            case .createStage:
                toolbarState.pendingAction = nil
                showCreateStageSheet = true
            case .deleteSelected:
                break // handled by list view
            }
        }
    }

    // MARK: - Header

    private var browserHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(api.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusBadge(text: api.endpointType, color: .blue)
                    Text(api.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Resources Tab

    @ViewBuilder
    private var resourcesTab: some View {
        if isLoadingResources && resources.isEmpty {
            ProgressView("Loading resources...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if resources.isEmpty {
            EmptyStateView(icon: "folder", message: "No resources")
        } else {
            VSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Resources")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button { showCreateResourceSheet = true } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.isReadOnly)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider()

                    List(resources, selection: $selectedResourceId) { resource in
                        HStack {
                            Text(resource.path)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            if !resource.methods.isEmpty {
                                HStack(spacing: 3) {
                                    ForEach(resource.methods, id: \.self) { method in
                                        StatusBadge(text: method, color: methodColor(method))
                                    }
                                }
                            }
                        }
                        .tag(resource.id)
                        .contextMenu {
                            Button("Copy Path") { copyToClipboard(resource.path) }
                            Button("Copy Resource ID") { copyToClipboard(resource.id) }
                            if !resource.isRoot {
                                Divider()
                                Button("Delete Resource", role: .destructive) {
                                    resourceToDelete = resource
                                }
                                .disabled(appState.isReadOnly)
                            }
                        }
                    }
                    .onChange(of: selectedResourceId) {
                        selectedResourceMethods = []
                        if let resId = selectedResourceId {
                            loadMethods(resourceId: resId)
                        }
                    }

                    Divider()
                    HStack {
                        Text("\(resources.count) resource\(resources.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 150)

                // Method detail pane
                VStack(spacing: 0) {
                    HStack {
                        Text("Methods")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button { showCreateMethodSheet = true } label: {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.isReadOnly || selectedResourceId == nil)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider()

                    if selectedResourceId == nil {
                        VStack(spacing: 8) {
                            Text("Select a resource to view methods")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoadingMethods {
                        ProgressView("Loading methods...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedResourceMethods.isEmpty {
                        VStack(spacing: 8) {
                            Text("No methods")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selectedResourceMethods) { method in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    StatusBadge(text: method.httpMethod, color: methodColor(method.httpMethod))
                                    Text("Auth: \(method.authorizationType)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if method.apiKeyRequired {
                                        StatusBadge(text: "API Key", color: .orange)
                                    }
                                    Spacer()
                                }
                                if let integration = method.integration {
                                    HStack(spacing: 6) {
                                        StatusBadge(text: integration.type, color: .purple)
                                        if !integration.uri.isEmpty {
                                            Text(integration.uri)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                }
                            }
                            .contextMenu {
                                Button("Copy Method") { copyToClipboard(method.httpMethod) }
                                if let integration = method.integration, !integration.uri.isEmpty {
                                    Button("Copy Integration URI") { copyToClipboard(integration.uri) }
                                }
                                Divider()
                                Button("Delete Method", role: .destructive) {
                                    methodToDelete = method.httpMethod
                                }
                                .disabled(appState.isReadOnly)
                            }
                        }
                    }
                }
                .frame(minHeight: 100)
            }
        }
    }

    // MARK: - Stages Tab

    @ViewBuilder
    private var stagesTab: some View {
        if isLoadingStages && stages.isEmpty {
            ProgressView("Loading stages...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stages.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "flag")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No stages")
                    .foregroundStyle(.secondary)
                Button("Create Stage") { showCreateStageSheet = true }
                    .disabled(appState.isReadOnly || deployments.isEmpty)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(stages) { stage in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(stage.stageName)
                            .fontWeight(.medium)
                        Spacer()
                        Text("Deployment: \(stage.deploymentId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !stage.description.isEmpty {
                        Text(stage.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Invoke URL") {
                                CopyableValue(text: stage.invokeUrl(apiId: api.id), monospaced: true)
                            }
                            LabeledContent("Path-style URL") {
                                CopyableValue(text: stage.pathStyleInvokeUrl(apiId: api.id, endpoint: appState.endpoint), monospaced: true)
                            }
                        }
                        .font(.caption)
                    }
                    if !stage.variables.isEmpty {
                        GroupBox("Stage Variables") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(stage.variables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    LabeledContent(key) {
                                        Text(value)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
                .contextMenu {
                    Button("Copy Stage Name") { copyToClipboard(stage.stageName) }
                    Button("Copy Invoke URL") { copyToClipboard(stage.invokeUrl(apiId: api.id)) }
                    Button("Copy Path-style URL") { copyToClipboard(stage.pathStyleInvokeUrl(apiId: api.id, endpoint: appState.endpoint)) }
                    Divider()
                    Button("Delete Stage", role: .destructive) {
                        stageToDelete = stage
                    }
                    .disabled(appState.isReadOnly)
                }
            }

            Divider()
            HStack {
                Text("\(stages.count) stage\(stages.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Deployments Tab

    @ViewBuilder
    private var deploymentsTab: some View {
        if isLoadingDeployments && deployments.isEmpty {
            ProgressView("Loading deployments...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if deployments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No deployments")
                    .foregroundStyle(.secondary)
                Button("Create Deployment") { showCreateDeploymentSheet = true }
                    .disabled(appState.isReadOnly)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(deployments) { deployment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(deployment.id)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if !deployment.createdDate.isEmpty {
                            Text(deployment.createdDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !deployment.description.isEmpty {
                        Text(deployment.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button("Copy Deployment ID") { copyToClipboard(deployment.id) }
                }
            }

            Divider()
            HStack {
                Text("\(deployments.count) deployment\(deployments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": .green
        case "POST": .blue
        case "PUT": .orange
        case "DELETE": .red
        case "PATCH": .purple
        case "OPTIONS": .gray
        case "ANY": .teal
        default: .secondary
        }
    }

    // MARK: - Data

    private func loadAll() {
        loadResources()
        loadDeployments()
        loadStages()
    }

    private func loadResources(silent: Bool = false) {
        if !silent { isLoadingResources = true }
        Task {
            do {
                let loaded = try await service.getResources(apiId: api.id)
                resources = loaded.sorted { $0.path < $1.path }
            } catch {
                if !silent { serviceError = error.asServiceError }
            }
            if !silent { isLoadingResources = false }
        }
    }

    private func loadDeployments(silent: Bool = false) {
        if !silent { isLoadingDeployments = true }
        Task {
            do {
                deployments = try await service.getDeployments(apiId: api.id)
            } catch {
                if !silent { serviceError = error.asServiceError }
            }
            if !silent { isLoadingDeployments = false }
        }
    }

    private func loadStages(silent: Bool = false) {
        if !silent { isLoadingStages = true }
        Task {
            do {
                stages = try await service.getStages(apiId: api.id)
            } catch {
                if !silent { serviceError = error.asServiceError }
            }
            if !silent { isLoadingStages = false }
        }
    }

    private func loadMethods(resourceId: String) {
        isLoadingMethods = true
        Task {
            do {
                guard let resource = resources.first(where: { $0.id == resourceId }) else {
                    isLoadingMethods = false
                    return
                }
                var methods: [APIMethod] = []
                for methodName in resource.methods {
                    do {
                        let method = try await service.getMethod(apiId: api.id, resourceId: resourceId, httpMethod: methodName)
                        methods.append(method)
                    } catch {
                        // Individual method load failure — skip it
                    }
                }
                selectedResourceMethods = methods
            }
            isLoadingMethods = false
        }
    }

    private func deleteResource(_ resource: APIResource) {
        Task {
            do {
                try await service.deleteResource(apiId: api.id, resourceId: resource.id)
                if selectedResourceId == resource.id {
                    selectedResourceId = nil
                    selectedResourceMethods = []
                }
                loadResources()
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteStage(_ stage: APIStage) {
        Task {
            do {
                try await service.deleteStage(apiId: api.id, stageName: stage.stageName)
                loadStages()
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteMethod(resourceId: String, httpMethod: String) {
        Task {
            do {
                try await service.deleteMethod(apiId: api.id, resourceId: resourceId, httpMethod: httpMethod)
                loadResources()
                loadMethods(resourceId: resourceId)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
