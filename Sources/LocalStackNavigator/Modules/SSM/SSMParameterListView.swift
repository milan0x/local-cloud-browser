import SwiftUI
import AppKit

struct SSMParameterListView: View {
    @ObservedObject var service: SSMService
    @ObservedObject var toolbarState: SSMToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedParameterIDs: Set<SSMParameter.ID>
    @Binding var activeParameter: SSMParameter?
    var restoreParameterName: String?

    @StateObject private var loader = ListLoader<SSMParameter>()
    private var parameters: [SSMParameter] { loader.items }
    @State private var showCreateSheet = false
    @State private var parametersToDelete: [SSMParameter] = []
    @State private var serviceError: ServiceError?
    @State private var parameterToShowDetail: SSMParameter?
    @State private var searchText = ""
    @State private var pendingSelectName: String?

    var body: some View {
        VStack(spacing: 0) {
            parameterListHeader
            Divider()
            parameterListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            SSMCreateParameterView(service: service, existingParameterNames: Set(loader.items.map(\.name))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadParameters(force: true) }
        }
        .deleteConfirmation(items: $parametersToDelete, noun: "Parameter") { items in
            if items.count == 1, let param = items.first {
                Text("Are you sure you want to delete \"\(param.name)\"?\n\nThis cannot be undone.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these parameters?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteParameters($0) }
        .sheet(item: $parameterToShowDetail) { parameter in
            SSMParameterDetailView(service: service, parameter: parameter)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadParameters() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && parametersToDelete.isEmpty && parameterToShowDetail == nil && !loader.isLoading }) {
            loadParameters(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedParameterIDs = []
            activeParameter = nil
            loader.items = []
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
        ListHeaderBar(
            title: "Parameters",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: parameterDeleteDisabled,
            deleteHelp: selectedParameterIDs.count <= 1 ? "Delete Parameter" : "Delete \(selectedParameterIDs.count) Parameters",
            onRefresh: { loadParameters(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { parametersToDelete = parameters.filter { selectedParameterIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var parameterListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: parameters.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading parameters...", onRetry: { loadParameters(force: true) }) {
            VStack(spacing: 0) {
                if parameters.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter parameters")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedParameterIDs) {
                    if parameters.isEmpty {
                        EmptyStateView(icon: "list.bullet.rectangle", message: "No parameters")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredParameters) { parameter in
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
                    .selectionForeground()
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
                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
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

                ListStatusBar(totalCount: parameters.count, selectedCount: selectedParameterIDs.count, noun: "parameter")
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
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.describeParameters() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreParameterName,
               let parameter = items.first(where: { $0.name == savedName }) {
                selectedParameterIDs = [parameter.id]
                activeParameter = parameter
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let parameter = items.first(where: { $0.name == name }) {
                selectedParameterIDs = [parameter.id]
                activeParameter = parameter
                pendingSelectName = nil
            }
        }
    }

    private func deleteParameters(_ targets: [SSMParameter]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteParameter(name: $0.name)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedParameterIDs.subtract(deleted)
                if let active = activeParameter, deleted.contains(active.id) {
                    activeParameter = nil
                }
                loadParameters(force: true)
            }
        }
    }
}
