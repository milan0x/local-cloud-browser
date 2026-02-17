import SwiftUI
import AppKit

struct LambdaFunctionListView: View {
    @ObservedObject var service: LambdaService
    @ObservedObject var toolbarState: LambdaToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedFunctionIDs: Set<LambdaFunction.ID>
    @Binding var activeFunction: LambdaFunction?
    var restoreFunctionName: String?

    @State private var showCreateSheet = false
    @State private var functionsToDelete: [LambdaFunction] = []
    @State private var serviceError: ServiceError?
    @State private var functionToShowDetail: LambdaFunction?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<LambdaFunction>()
    private var functions: [LambdaFunction] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            functionListHeader
            Divider()
            functionListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            LambdaCreateFunctionView(service: service, existingFunctionNames: Set(functions.map(\.functionName)))
                .onDisappear { loadFunctions(force: true) }
        }
        .deleteConfirmation(items: $functionsToDelete, noun: "Function") { items in
            if items.count == 1, let fn = items.first {
                Text("Are you sure you want to delete \"\(fn.functionName)\"?\n\nThis cannot be undone.")
            } else {
                let names = items.map(\.functionName).joined(separator: "\n")
                Text("Are you sure you want to delete these functions?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteFunctions($0) }
        .sheet(item: $functionToShowDetail) { function in
            LambdaFunctionDetailView(service: service, function: function)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadFunctions() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && functionsToDelete.isEmpty && functionToShowDetail == nil && !loader.isLoading }) {
            loadFunctions(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedFunctionIDs = []
            activeFunction = nil
            loader.items = []
            loadFunctions(force: true)
        }
        .syncSelection(selectedFunctionIDs, items: functions, activeItem: $activeFunction)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createFunction:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteSelected:
                toolbarState.pendingAction = nil
                if let active = activeFunction {
                    functionsToDelete = [active]
                }
            case .viewDetails, .invoke:
                break // handled by right pane
            }
        }
    }

    private var functionDeleteDisabled: Bool {
        appState.isReadOnly || selectedFunctionIDs.isEmpty
    }

    private var filteredFunctions: [LambdaFunction] {
        guard !searchText.isEmpty else { return functions }
        let query = searchText.lowercased()
        return functions.filter { $0.functionName.lowercased().contains(query) }
    }

    // MARK: - Header

    private var functionListHeader: some View {
        ListHeaderBar(
            title: "Functions",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            deleteDisabled: functionDeleteDisabled,
            deleteHelp: selectedFunctionIDs.count <= 1 ? "Delete Function" : "Delete \(selectedFunctionIDs.count) Functions",
            onRefresh: { loadFunctions(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { functionsToDelete = functions.filter { selectedFunctionIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var functionListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: functions.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading functions...", onRetry: { loadFunctions(force: true) }) {
            VStack(spacing: 0) {
                if functions.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter functions")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedFunctionIDs) {
                    if functions.isEmpty {
                        EmptyStateView(icon: "function", message: "No functions")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredFunctions) { function in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(function.functionName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if !function.runtime.isEmpty {
                                StatusBadge(text: function.runtime, color: runtimeColor(function))
                            }
                            if !function.description.isEmpty {
                                Text(function.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(selectedFunctionIDs.contains(function.id) ? Color.white : Color.primary)
                    .tag(function.id)
                    .contextMenu {
                        Button("View Details") {
                            functionToShowDetail = function
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(function.functionName) }
                        if !function.functionArn.isEmpty {
                            Button("Copy ARN") { copyToClipboard(function.functionArn) }
                        }
                        Menu("Copy as AWS CLI") {
                            Button("Get Function") {
                                copyToClipboard(function.getFunctionCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Invoke") {
                                copyToClipboard(function.invokeCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Functions") {
                                copyToClipboard(LambdaFunction.listFunctionsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Function") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedFunctionIDs.count > 1 && selectedFunctionIDs.contains(function.id) {
                            let selected = functions.filter { selectedFunctionIDs.contains($0.id) }
                            Button("Delete \(selected.count) Functions", role: .destructive) {
                                functionsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                functionsToDelete = [function]
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
                    Button("Create Function") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
                .background(DoubleClickDetector {
                    if selectedFunctionIDs.count == 1,
                       let id = selectedFunctionIDs.first,
                       let function = functions.first(where: { $0.id == id }) {
                        functionToShowDetail = function
                    }
                })

                ListStatusBar(totalCount: functions.count, selectedCount: selectedFunctionIDs.count, noun: "function")
            }
        }
    }

    private func runtimeColor(_ function: LambdaFunction) -> Color {
        switch function.runtimeBadgeColor {
        case .python: .blue
        case .nodejs: .green
        case .java: .orange
        case .dotnet: .purple
        case .ruby: .red
        case .custom: .gray
        }
    }

    // MARK: - Data

    private func loadFunctions(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listFunctions() },
            sort: { $0.functionName.localizedStandardCompare($1.functionName) == .orderedAscending }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreFunctionName,
               let function = items.first(where: { $0.functionName == savedName }) {
                selectedFunctionIDs = [function.id]
                activeFunction = function
            }
            loader.hasRestoredSession = true
        }
    }

    private func deleteFunctions(_ targets: [LambdaFunction]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteFunction(name: $0.functionName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                selectedFunctionIDs.subtract(deleted)
                if let active = activeFunction, deleted.contains(active.id) {
                    activeFunction = nil
                }
                loadFunctions(force: true)
            }
        }
    }

}
