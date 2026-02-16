import SwiftUI
import AppKit

struct ConfigRecorderListView: View {
    @ObservedObject var service: ConfigService
    @ObservedObject var toolbarState: ConfigToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedRecorderIDs: Set<ConfigurationRecorder.ID>
    @Binding var activeRecorder: ConfigurationRecorder?
    var restoreRecorderName: String?

    @State private var recorders: [ConfigurationRecorder] = []
    @State private var statuses: [String: ConfigurationRecorderStatus] = [:]
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var recordersToDelete: [ConfigurationRecorder] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            recorderListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            ConfigCreateRecorderView(service: service)
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
        .onAutoRefresh(canRefresh: { !showCreateSheet && recordersToDelete.isEmpty && !isLoading }) {
            loadRecorders(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedRecorderIDs = []
            activeRecorder = nil
            recorders = []
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

    @ViewBuilder
    private var recorderListContent: some View {
        if isLoading && recorders.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading recorders...")
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, recorders.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadRecorders(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if recorders.isEmpty {
            EmptyStateView(icon: "gearshape.2", message: "No recorders", secondaryMessage: "Recorders are mocked — resource changes are NOT recorded")
            .contextMenu {
                Button("Create Recorder") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if recorders.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter recorders")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredRecorders, selection: $selectedRecorderIDs) { recorder in
                    HStack {
                        Text(recorder.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        recordingBadge(for: recorder.name)
                    }
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        ConnectionLostBanner()
                    }
                }
                .contextMenu {
                    Button("Create Recorder") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

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

    @ViewBuilder
    private func recordingBadge(for name: String) -> some View {
        if let status = statuses[name] {
            StatusBadge(text: status.recording ? "RECORDING" : "STOPPED", color: status.recording ? .green : .gray)
        }
    }

    // MARK: - Data

    private func loadRecorders(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.describeConfigurationRecorders()
                let freshRecorders = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if recorders != freshRecorders {
                    recorders = freshRecorders
                }
                // Load statuses
                let loadedStatuses = try await service.describeConfigurationRecorderStatus()
                var map: [String: ConfigurationRecorderStatus] = [:]
                for s in loadedStatuses { map[s.name] = s }
                statuses = map

                if !hasRestoredSession, let savedName = restoreRecorderName,
                   let recorder = recorders.first(where: { $0.name == savedName }) {
                    selectedRecorderIDs = [recorder.id]
                    activeRecorder = recorder
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
