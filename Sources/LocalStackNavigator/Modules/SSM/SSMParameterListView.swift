import SwiftUI
import AppKit

struct SSMParameterListView: View {
    @ObservedObject var service: SSMService
    @ObservedObject var toolbarState: SSMToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedParameterIDs: Set<SSMParameter.ID>
    @Binding var activeParameter: SSMParameter?
    var restoreParameterName: String?

    @State private var parameters: [SSMParameter] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var parametersToDelete: [SSMParameter] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var parameterToShowDetail: SSMParameter?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            parameterListHeader
            Divider()
            parameterListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SSMCreateParameterView(service: service, existingParameterNames: Set(parameters.map(\.name)))
                .onDisappear { loadParameters(force: true) }
        }
        .alert(
            parametersToDelete.count == 1
                ? "Delete Parameter"
                : "Delete \(parametersToDelete.count) Parameters",
            isPresented: Binding(
                get: { !parametersToDelete.isEmpty },
                set: { if !$0 { parametersToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteParameters(parametersToDelete)
            }
            Button("Cancel", role: .cancel) {
                parametersToDelete = []
            }
        } message: {
            if parametersToDelete.count == 1, let param = parametersToDelete.first {
                Text("Are you sure you want to delete \"\(param.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = parametersToDelete.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these parameters?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $parameterToShowDetail) { parameter in
            SSMParameterDetailView(service: service, parameter: parameter)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadParameters() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && parametersToDelete.isEmpty && parameterToShowDetail == nil && !isLoading }) {
            loadParameters(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedParameterIDs = []
            activeParameter = nil
            parameters = []
            loadParameters(force: true)
        }
        .syncSelection(selectedParameterIDs, items: parameters, activeItem: $activeParameter)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createParameter:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeParameter {
                    parametersToDelete = [active]
                }
            case .viewDetails:
                break // handled by right pane
            }
        }
    }

    private var parameterDeleteDisabled: Bool {
        appState.isReadOnly || selectedParameterIDs.isEmpty
    }

    private var filteredParameters: [SSMParameter] {
        guard !searchText.isEmpty else { return parameters }
        let query = searchText.lowercased()
        return parameters.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Header

    private var parameterListHeader: some View {
        HStack {
            Text("Parameters")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadParameters(force: true)
            }

            Spacer()

            ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
                showCreateSheet = true
            }

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadParameters(force: true)
            }

            ListHeaderButton("trash", color: .red, isDisabled: parameterDeleteDisabled, help: selectedParameterIDs.count <= 1 ? "Delete Parameter" : "Delete \(selectedParameterIDs.count) Parameters") {
                parametersToDelete = parameters.filter { selectedParameterIDs.contains($0.id) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var parameterListContent: some View {
        if isLoading && parameters.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading parameters...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, parameters.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadParameters(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if parameters.isEmpty {
            EmptyStateView(icon: "list.bullet.rectangle", message: "No parameters")
            .contextMenu {
                Button("Create Parameter") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if parameters.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter parameters")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredParameters, selection: $selectedParameterIDs) { parameter in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(parameter.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            StatusBadge(text: parameter.displayType, color: typeColor(parameter.type))
                            if let desc = parameter.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .tag(parameter.id)
                    .contextMenu {
                        Button("View Details") {
                            parameterToShowDetail = parameter
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(parameter.name) }
                        if let arn = parameter.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Get Parameter") {
                                copyToClipboard(parameter.getParameterCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Describe Parameters") {
                                copyToClipboard(parameter.describeParametersCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Parameter") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedParameterIDs.count > 1 && selectedParameterIDs.contains(parameter.id) {
                            let selected = parameters.filter { selectedParameterIDs.contains($0.id) }
                            Button("Delete \(selected.count) Parameters", role: .destructive) {
                                parametersToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                parametersToDelete = [parameter]
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
                    Button("Create Parameter") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedParameterIDs.count == 1,
                       let id = selectedParameterIDs.first,
                       let parameter = parameters.first(where: { $0.id == id }) {
                        parameterToShowDetail = parameter
                    }
                })

                // Status bar
                Divider()
                HStack {
                    Text("\(parameters.count) parameter\(parameters.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedParameterIDs.count > 1 {
                        Text("(\(selectedParameterIDs.count) selected)")
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

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "SecureString": .orange
        case "StringList": .purple
        default: .gray
        }
    }

    // MARK: - Data

    private func loadParameters(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.describeParameters()
                let freshParameters = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if parameters != freshParameters {
                    parameters = freshParameters
                }
                if !hasRestoredSession, let savedName = restoreParameterName,
                   let parameter = parameters.first(where: { $0.name == savedName }) {
                    selectedParameterIDs = [parameter.id]
                    activeParameter = parameter
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

    private func deleteParameters(_ targets: [SSMParameter]) {
        Task {
            var deletedIDs: Set<SSMParameter.ID> = []
            for parameter in targets {
                do {
                    try await service.deleteParameter(name: parameter.name)
                    deletedIDs.insert(parameter.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedParameterIDs.subtract(deletedIDs)
                if let active = activeParameter, deletedIDs.contains(active.id) {
                    activeParameter = nil
                }
                loadParameters(force: true)
            }
        }
    }
}
