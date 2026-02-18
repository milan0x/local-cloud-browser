import SwiftUI
import AppKit

struct ConfigRecorderListView: View {
    @ObservedObject var service: ConfigService
    @ObservedObject var toolbarState: ConfigToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedRecorderIDs: Set<ConfigurationRecorder.ID>
    @Binding var activeRecorder: ConfigurationRecorder?
    var restoreRecorderName: String?

    @StateObject private var loader = ListLoader<ConfigurationRecorder>()
    private var recorders: [ConfigurationRecorder] { loader.items }
    @State private var statuses: [String: ConfigurationRecorderStatus] = [:]
    @State private var showCreateSheet = false
    @State private var pendingSelectName: String?
    @State private var recordersToDelete: [ConfigurationRecorder] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            recorderListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            ConfigCreateRecorderView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadRecorders(force: true) }
        }
        .alert(
            recordersToDelete.count == 1
                ? "Delete Recorder"
                : "Delete \(recordersToDelete.count) Recorders",
            isPresented: Binding(
                get: { !recordersToDelete.isEmpty },
                set: { if !$0 { recordersToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteRecorders(recordersToDelete)
            }
            Button("Cancel", role: .cancel) {
                recordersToDelete = []
            }
        } message: {
            if recordersToDelete.count == 1, let recorder = recordersToDelete.first {
                Text("Are you sure you want to delete recorder \"\(recorder.name)\"?\n\nThis action cannot be undone.")
            } else {
                Text("Are you sure you want to delete \(recordersToDelete.count) recorders?\n\nThis action cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadRecorders() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && recordersToDelete.isEmpty && !loader.isLoading }) {
            loadRecorders(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedRecorderIDs = []
            activeRecorder = nil
            loader.items = []
            statuses = [:]
            loadRecorders(force: true)
        }
        .syncSelection(selectedRecorderIDs, items: recorders, activeItem: $activeRecorder)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createRecorder:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteRecorder:
                toolbarState.pendingAction = nil
                if let active = activeRecorder {
                    recordersToDelete = [active]
                }
            case .createChannel, .deleteChannel:
                break
            }
        }
    }

    private var filteredRecorders: [ConfigurationRecorder] {
        guard !searchText.isEmpty else { return recorders }
        let query = searchText.lowercased()
        return recorders.filter {
            $0.name.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var recorderListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: recorders.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading recorders...", onRetry: { loadRecorders(force: true) }) {
            VStack(spacing: 0) {
                if recorders.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter recorders")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedRecorderIDs) {
                    if recorders.isEmpty {
                        EmptyStateView(icon: "gearshape.2", message: "No recorders", secondaryMessage: "Recorders are mocked — resource changes are NOT recorded")
                            .listRowSeparator(.hidden)
                    }
                    ForEach(filteredRecorders) { recorder in
                    HStack {
                        Text(recorder.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        recordingBadge(for: recorder.name)
                    }
                    .selectionForeground()
                    .tag(recorder.id)
                    .contextMenu {
                        Button("Copy Name") { copyToClipboard(recorder.name) }
                        Menu("Copy as AWS CLI") {
                            Button("Describe Recorder") {
                                copyToClipboard(recorder.describeRecorderCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Recorders") {
                                copyToClipboard(ConfigurationRecorder.listRecordersCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Create Recorder") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Delete", role: .destructive) {
                            recordersToDelete = [recorder]
                        }
                        .disabled(appState.isReadOnly)
                    }
                    }

                }
                .overlay(alignment: .bottom) {
                    if loader.errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Recorder") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                if !recorders.isEmpty {
                    Divider()
                    HStack {
                        Text("\(recorders.count) recorder\(recorders.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func recordingBadge(for name: String) -> some View {
        if let status = statuses[name] {
            StatusBadge(text: status.recording ? "RECORDING" : "STOPPED", color: status.recording ? .green : .gray)
        }
    }

    // MARK: - Data

    private func loadRecorders(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.describeConfigurationRecorders() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            // Load statuses
            if let loadedStatuses = try? await service.describeConfigurationRecorderStatus() {
                var map: [String: ConfigurationRecorderStatus] = [:]
                for s in loadedStatuses { map[s.name] = s }
                statuses = map
            }

            if !loader.hasRestoredSession, let savedName = restoreRecorderName,
               let recorder = items.first(where: { $0.name == savedName }) {
                selectedRecorderIDs = [recorder.id]
                activeRecorder = recorder
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let recorder = items.first(where: { $0.name == name }) {
                selectedRecorderIDs = [recorder.id]
                activeRecorder = recorder
                pendingSelectName = nil
            }
        }
    }

    private func deleteRecorders(_ targets: [ConfigurationRecorder]) {
        Task {
            var deletedIDs: Set<ConfigurationRecorder.ID> = []
            for recorder in targets {
                do {
                    try await service.deleteConfigurationRecorder(name: recorder.name)
                    deletedIDs.insert(recorder.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedRecorderIDs.subtract(deletedIDs)
                if let active = activeRecorder, deletedIDs.contains(active.id) {
                    activeRecorder = nil
                }
                loadRecorders(force: true)
            }
        }
    }
}
