import SwiftUI
import AppKit

struct TranscribeJobListView: View {
    @ObservedObject var service: TranscribeService
    @ObservedObject var toolbarState: TranscribeToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var selectedJobIDs: Set<TranscriptionJob.ID>
    @Binding var activeJob: TranscriptionJob?
    var restoreJobName: String?

    @StateObject private var loader = ListLoader<TranscriptionJob>()
    private var jobs: [TranscriptionJob] { loader.items }
    @State private var showCreateSheet = false
    @State private var jobsToDelete: [TranscriptionJob] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @State private var pendingSelectName: String?

    var body: some View {
        VStack(spacing: 0) {
            jobListHeader
            Divider()
            jobListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            TranscribeCreateJobView(service: service, onCreate: { pendingSelectName = $0 })
                .onDisappear { loadJobs(force: true) }
        }
        .deleteConfirmation(items: $jobsToDelete, noun: "Transcription Job") { items in
            if items.count == 1, let job = items.first {
                Text("Are you sure you want to delete transcription job \"\(job.jobName)\"?")
            } else {
                Text("Are you sure you want to delete \(items.count) transcription jobs?")
            }
        } onDelete: { deleteJobs($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadJobs() }
        .onAutoRefresh(canRefresh: { !showCreateSheet && jobsToDelete.isEmpty && !loader.isLoading }) {
            loadJobs(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedJobIDs = []
            activeJob = nil
            loader.items = []
            loadJobs(force: true)
        }
        .syncSelection(selectedJobIDs, items: jobs, activeItem: $activeJob)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createJob:
                toolbarState.pendingAction = nil
                showCreateSheet = true
            case .deleteJob:
                toolbarState.pendingAction = nil
                if let active = activeJob {
                    jobsToDelete = [active]
                }
            }
        }
    }

    private var jobDeleteDisabled: Bool {
        appState.isReadOnly || selectedJobIDs.isEmpty
    }

    private var filteredJobs: [TranscriptionJob] {
        guard !searchText.isEmpty else { return jobs }
        let query = searchText.lowercased()
        return jobs.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.languageCode.lowercased().contains(query) ||
            $0.jobStatus.lowercased().contains(query)
        }
    }

    // MARK: - Header

    private var jobListHeader: some View {
        ListHeaderBar(
            title: "Jobs",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: jobs.count,
            deleteDisabled: jobDeleteDisabled,
            deleteHelp: selectedJobIDs.count <= 1 ? "Delete Transcription Job" : "Delete \(selectedJobIDs.count) Jobs",
            onRefresh: { loadJobs(force: true) },
            onCreate: { showCreateSheet = true },
            onDelete: { jobsToDelete = jobs.filter { selectedJobIDs.contains($0.id) } }
        )
    }

    // MARK: - Content

    private var jobListContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: jobs.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading jobs...", emptyIcon: "waveform", emptyMessage: "No transcription jobs", onRetry: { loadJobs(force: true) }) {
            VStack(spacing: 0) {
                if jobs.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter jobs")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: $selectedJobIDs) {
                    ForEach(filteredJobs) { job in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.jobName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                if !job.languageCode.isEmpty {
                                    Text(job.languageCode)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !job.mediaFormat.isEmpty {
                                    formatBadge(for: job)
                                }
                            }
                        }
                        Spacer()
                        statusBadge(for: job)
                    }
                    .selectionForeground()
                    .tag(job.id)
                    .contextMenu {
                        Button("Copy Job Name") { copyToClipboard(job.jobName) }
                        Menu("Copy as AWS CLI") {
                            Button("Get Transcription Job") {
                                copyToClipboard(job.getJobCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("List Transcription Jobs") {
                                copyToClipboard(TranscriptionJob.listJobsCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                            Button("Delete Transcription Job") {
                                copyToClipboard(job.deleteJobCLI(endpointUrl: appState.endpoint, region: appState.region))
                            }
                        }
                        Divider()
                        Button("Start Transcription Job") {
                            showCreateSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        if selectedJobIDs.count > 1 && selectedJobIDs.contains(job.id) {
                            let selected = jobs.filter { selectedJobIDs.contains($0.id) }
                            Button("Delete \(selected.count) Jobs", role: .destructive) {
                                jobsToDelete = selected
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Delete", role: .destructive) {
                                jobsToDelete = [job]
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
                    Button("Start Transcription Job") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                ListStatusBar(totalCount: jobs.count, selectedCount: selectedJobIDs.count, noun: "job")
            }
        }
    }

    private func statusBadge(for job: TranscriptionJob) -> some View {
        StatusBadge(text: job.jobStatus, color: statusColor(job.jobStatus))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "COMPLETED": .green
        case "IN_PROGRESS": .blue
        case "QUEUED": .orange
        case "FAILED": .red
        default: .gray
        }
    }

    private func formatBadge(for job: TranscriptionJob) -> some View {
        StatusBadge(text: job.displayFormat, color: .purple)
    }

    // MARK: - Data

    private func loadJobs(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listTranscriptionJobs() },
            sort: { ($0.creationTime ?? .distantPast) > ($1.creationTime ?? .distantPast) }
        ) { [self] items in
            if !loader.hasRestoredSession, let savedName = restoreJobName,
               let job = items.first(where: { $0.jobName == savedName }) {
                selectedJobIDs = [job.id]
                activeJob = job
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let job = items.first(where: { $0.jobName == name }) {
                selectedJobIDs = [job.id]
                activeJob = job
                pendingSelectName = nil
            }
        }
    }

    private func deleteJobs(_ targets: [TranscriptionJob]) {
        Task {
            let (deleted, error) = await batchDelete(targets) {
                try await service.deleteTranscriptionJob(name: $0.jobName)
            }
            if let error { serviceError = error }
            if !deleted.isEmpty {
                licenseManager.decrementCreateCount(for: .transcribe, by: deleted.count)
                selectedJobIDs.subtract(deleted)
                if let active = activeJob, deleted.contains(active.id) {
                    activeJob = nil
                }
                loadJobs(force: true)
            }
        }
    }
}
