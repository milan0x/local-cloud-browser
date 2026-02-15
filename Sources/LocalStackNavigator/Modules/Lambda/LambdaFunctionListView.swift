import SwiftUI
import AppKit

struct LambdaFunctionListView: View {
    @ObservedObject var service: LambdaService
    @ObservedObject var toolbarState: LambdaToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedFunctionIDs: Set<LambdaFunction.ID>
    @Binding var activeFunction: LambdaFunction?
    var restoreFunctionName: String?

    @State private var functions: [LambdaFunction] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var functionsToDelete: [LambdaFunction] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var functionToShowDetail: LambdaFunction?
    @State private var searchText = ""

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
        .alert(
            functionsToDelete.count == 1
                ? "Delete Function"
                : "Delete \(functionsToDelete.count) Functions",
            isPresented: Binding(
                get: { !functionsToDelete.isEmpty },
                set: { if !$0 { functionsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteFunctions(functionsToDelete)
            }
            Button("Cancel", role: .cancel) {
                functionsToDelete = []
            }
        } message: {
            if functionsToDelete.count == 1, let fn = functionsToDelete.first {
                Text("Are you sure you want to delete \"\(fn.functionName)\"?\n\nThis cannot be undone.")
            } else {
                let names = functionsToDelete.map(\.functionName).joined(separator: "\n")
                Text("Are you sure you want to delete these functions?\n\n\(names)\n\nThis cannot be undone.")
            }
        }
        .sheet(item: $functionToShowDetail) { function in
            LambdaFunctionDetailView(service: service, function: function)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadFunctions() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && functionsToDelete.isEmpty && functionToShowDetail == nil && !isLoading else { return }
            loadFunctions(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedFunctionIDs = []
            activeFunction = nil
            functions = []
            loadFunctions(force: true)
        }
        .onChange(of: appState.region) {
            selectedFunctionIDs = []
            activeFunction = nil
            functions = []
            loadFunctions(force: true)
        }
        .onChange(of: selectedFunctionIDs) {
            if selectedFunctionIDs.count == 1, let id = selectedFunctionIDs.first {
                activeFunction = functions.first { $0.id == id }
            } else {
                activeFunction = nil
            }
        }
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
        HStack {
            Text("Functions")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadFunctions(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadFunctions(force: true)
            }

            Button {
                functionsToDelete = functions.filter { selectedFunctionIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(functionDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(functionDeleteDisabled)
            .help(selectedFunctionIDs.count <= 1 ? "Delete Function" : "Delete \(selectedFunctionIDs.count) Functions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var functionListContent: some View {
        if isLoading && functions.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading functions...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, functions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadFunctions(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if functions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "function")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No functions")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Create Function") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if functions.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter functions")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredFunctions, selection: $selectedFunctionIDs) { function in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(function.functionName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if !function.runtime.isEmpty {
                                Text(function.runtime)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(runtimeColor(function).opacity(0.15), in: Capsule())
                                    .foregroundStyle(runtimeColor(function))
                            }
                            if !function.description.isEmpty {
                                Text(function.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
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

                // Status bar
                Divider()
                HStack {
                    Text("\(functions.count) function\(functions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedFunctionIDs.count > 1 {
                        Text("(\(selectedFunctionIDs.count) selected)")
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
                let loaded = try await service.listFunctions()
                let freshFunctions = loaded.sorted { $0.functionName.localizedStandardCompare($1.functionName) == .orderedAscending }
                if functions != freshFunctions {
                    functions = freshFunctions
                }
                if !hasRestoredSession, let savedName = restoreFunctionName,
                   let function = functions.first(where: { $0.functionName == savedName }) {
                    selectedFunctionIDs = [function.id]
                    activeFunction = function
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

    private func deleteFunctions(_ targets: [LambdaFunction]) {
        Task {
            var deletedIDs: Set<LambdaFunction.ID> = []
            for function in targets {
                do {
                    try await service.deleteFunction(name: function.functionName)
                    deletedIDs.insert(function.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedFunctionIDs.subtract(deletedIDs)
                if let active = activeFunction, deletedIDs.contains(active.id) {
                    activeFunction = nil
                }
                loadFunctions(force: true)
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
