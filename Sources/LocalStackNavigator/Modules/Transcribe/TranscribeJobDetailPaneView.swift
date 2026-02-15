import SwiftUI
import AppKit

struct TranscribeJobDetailPaneView: View {
    @ObservedObject var service: TranscribeService
    let job: TranscriptionJob
    @EnvironmentObject private var appState: AppState

    @State private var detail: TranscriptionJob?
    @State private var transcriptText: String?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && detail == nil {
                ProgressView("Loading job details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        jobInfoSection
                        mediaSection
                        if !effectiveJob.failureReason.isEmpty {
                            errorSection(effectiveJob.failureReason)
                        }
                        transcriptSection
                    }
                    .padding(16)
                }
            }
        }
        .task { loadDetails() }
        .onChange(of: job.jobName) {
            detail = nil
            transcriptText = nil
            loadDetails()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !isLoading else { return }
            loadDetails(silent: true)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    private var effectiveJob: TranscriptionJob {
        detail ?? job
    }

    // MARK: - Job Info Section

    private var jobInfoSection: some View {
        GroupBox("Job Information") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Name") {
                    CopyableValue(text: effectiveJob.jobName, monospaced: true)
                }
                labeledRow("Status") {
                    statusBadge
                }
                if !effectiveJob.languageCode.isEmpty {
                    labeledRow("Language") {
                        Text("\(effectiveJob.displayLanguage) (\(effectiveJob.languageCode))")
                    }
                }
                if !effectiveJob.mediaFormat.isEmpty {
                    labeledRow("Format") {
                        formatBadge
                    }
                }
                if let rate = effectiveJob.mediaSampleRateHertz {
                    labeledRow("Sample Rate") {
                        Text("\(rate) Hz")
                            .font(.body.monospaced())
                    }
                }
                if let date = effectiveJob.creationTime {
                    labeledRow("Created") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if let date = effectiveJob.startTime {
                    labeledRow("Started") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if let date = effectiveJob.completionTime {
                    labeledRow("Completed") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
        }
    }

    private var statusBadge: some View {
        Text(effectiveJob.jobStatus)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch effectiveJob.jobStatus {
        case "COMPLETED": .green
        case "IN_PROGRESS": .blue
        case "QUEUED": .orange
        case "FAILED": .red
        default: .gray
        }
    }

    private var formatBadge: some View {
        Text(effectiveJob.displayFormat)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.12), in: Capsule())
            .foregroundStyle(.purple)
    }

    // MARK: - Media Section

    private var mediaSection: some View {
        GroupBox("Media") {
            VStack(alignment: .leading, spacing: 8) {
                if !effectiveJob.mediaFileUri.isEmpty {
                    labeledRow("Input URI") {
                        CopyableValue(text: effectiveJob.mediaFileUri, font: .caption, monospaced: true)
                    }
                }
                if !effectiveJob.outputBucketName.isEmpty {
                    labeledRow("Output Bucket") {
                        CopyableValue(text: effectiveJob.outputBucketName, monospaced: true)
                    }
                }
                if !effectiveJob.transcriptFileUri.isEmpty {
                    labeledRow("Transcript URI") {
                        CopyableValue(text: effectiveJob.transcriptFileUri, font: .caption, monospaced: true)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ reason: String) -> some View {
        GroupBox("Error") {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(4)
        }
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        GroupBox("Transcript") {
            if effectiveJob.jobStatus == "COMPLETED" {
                if let text = transcriptText {
                    if text.isEmpty {
                        Text("No transcript content available")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                } label: {
                                    Label("Copy Transcript", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            Text(text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading transcript...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            } else if effectiveJob.jobStatus == "IN_PROGRESS" || effectiveJob.jobStatus == "QUEUED" {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcription \(effectiveJob.jobStatus == "QUEUED" ? "queued" : "in progress")...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if effectiveJob.jobStatus == "FAILED" {
                Text("Transcription failed \u{2014} no transcript available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Text("Transcript not available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadDetails(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                let loaded = try await service.getTranscriptionJob(name: job.jobName)
                detail = loaded

                // Fetch transcript if job is completed and has a transcript URI
                if loaded.jobStatus == "COMPLETED" && !loaded.transcriptFileUri.isEmpty {
                    do {
                        let text = try await service.fetchTranscript(from: loaded.transcriptFileUri)
                        transcriptText = text
                    } catch {
                        transcriptText = ""
                    }
                } else if loaded.jobStatus == "COMPLETED" {
                    transcriptText = ""
                } else {
                    transcriptText = nil
                }
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }
}
