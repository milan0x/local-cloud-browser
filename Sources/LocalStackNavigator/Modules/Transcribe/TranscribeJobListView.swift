import SwiftUI
import AppKit

struct TranscribeJobListView: View {
    @ObservedObject var service: TranscribeService
    @ObservedObject var toolbarState: TranscribeToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedJobIDs: Set<TranscriptionJob.ID>
    @Binding var activeJob: TranscriptionJob?
    var restoreJobName: String?

    @State private var jobs: [TranscriptionJob] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var jobsToDelete: [TranscriptionJob] = []
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            jobListHeader
            Divider()
            jobListContent
        }
        .sheet(isPresented: $showCreateSheet) {
            TranscribeCreateJobView(service: service)
                .onDisappear { loadJobs(force: true) }
        }
        .alert(
            jobsToDelete.count == 1
                ? "Delete Transcription Job"
                : "Delete \(jobsToDelete.count) Transcription Jobs",
            isPresented: Binding(
                get: { !jobsToDelete.isEmpty },
                set: { if !$0 { jobsToDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                deleteJobs(jobsToDelete)
            }
            Button("Cancel", role: .cancel) {
                jobsToDelete = []
            }
        } message: {
            if jobsToDelete.count == 1, let job = jobsToDelete.first {
                Text("Are you sure you want to delete transcription job \"\(job.jobName)\"?")
            } else {
                Text("Are you sure you want to delete \(jobsToDelete.count) transcription jobs?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadJobs() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateSheet && jobsToDelete.isEmpty && !isLoading else { return }
            loadJobs(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            selectedJobIDs = []
            activeJob = nil
            jobs = []
            loadJobs(force: true)
        }
        .onChange(of: appState.region) {
            selectedJobIDs = []
            activeJob = nil
            jobs = []
            loadJobs(force: true)
        }
        .onChange(of: selectedJobIDs) {
            if selectedJobIDs.count == 1, let id = selectedJobIDs.first {
                activeJob = jobs.first { $0.id == id }
            } else {
                activeJob = nil
            }
        }
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
        HStack {
            Text("Jobs")
                .font(.headline)

            AutoRefreshIndicatorView(manager: appState.autoRefresh) {
                loadJobs(force: true)
            }

            Spacer()

            Button { showCreateSheet = true } label: {
                Image(systemName: "plus")
                    .foregroundStyle(appState.isReadOnly ? .gray : Color.primary)
            }
            .buttonStyle(.borderless)
            .disabled(appState.isReadOnly)

            AutoRefreshMenuView(interval: Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })) {
                loadJobs(force: true)
            }

            Button {
                jobsToDelete = jobs.filter { selectedJobIDs.contains($0.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(jobDeleteDisabled ? .gray : .red)
            }
            .buttonStyle(.borderless)
            .disabled(jobDeleteDisabled)
            .help(selectedJobIDs.count <= 1 ? "Delete Transcription Job" : "Delete \(selectedJobIDs.count) Jobs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var jobListContent: some View {
        if isLoading && jobs.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading jobs...")
                if appState.connectionError != nil {
                    Label("Connection lost \u{2014} retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, jobs.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadJobs(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if jobs.isEmpty {
            EmptyStateView(icon: "waveform", message: "No transcription jobs")
            .contextMenu {
                Button("Start Transcription Job") {
                    showCreateSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if jobs.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter jobs")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredJobs, selection: $selectedJobIDs) { job in
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
                            Button("Delete (\(selected.count) Jobs)", role: .destructive) {
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
                .overlay(alignment: .bottom) {
                    if errorMessage != nil {
                        connectionLostBanner
                    }
                }
                .contextMenu {
                    Button("Start Transcription Job") {
                        showCreateSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedJobIDs.count > 1 {
                        Text("(\(selectedJobIDs.count) selected)")
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

    private var connectionLostBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost \u{2014} showing cached data")
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

    private func loadJobs(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listTranscriptionJobs()
                let freshJobs = loaded.sorted {
                    ($0.creationTime ?? .distantPast) > ($1.creationTime ?? .distantPast)
                }
                if jobs != freshJobs {
                    jobs = freshJobs
                }
                if !hasRestoredSession, let savedName = restoreJobName,
                   let job = jobs.first(where: { $0.jobName == savedName }) {
                    selectedJobIDs = [job.id]
                    activeJob = job
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

    private func deleteJobs(_ targets: [TranscriptionJob]) {
        Task {
            var deletedIDs: Set<TranscriptionJob.ID> = []
            for job in targets {
                do {
                    try await service.deleteTranscriptionJob(name: job.jobName)
                    deletedIDs.insert(job.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                selectedJobIDs.subtract(deletedIDs)
                if let active = activeJob, deletedIDs.contains(active.id) {
                    activeJob = nil
                }
                loadJobs(force: true)
            }
        }
    }
}
