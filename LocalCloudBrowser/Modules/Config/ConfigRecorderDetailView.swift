import SwiftUI

struct ConfigRecorderDetailView: View {
    @ObservedObject var service: ConfigService
    let recorder: ConfigurationRecorder
    @EnvironmentObject private var appState: AppState

    @State private var status: ConfigurationRecorderStatus?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        Group {
            if isLoading && status == nil {
                ProgressView("Loading recorder details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        recorderInfoSection
                        statusSection
                    }
                    .padding(16)
                }
            }
        }
        .task { loadStatus() }
        .onChange(of: recorder.name) {
            status = nil
            loadStatus()
        }
        .onAutoRefresh(canRefresh: { !isLoading }) {
            loadStatus(silent: true)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Recorder Info

    private var recorderInfoSection: some View {
        GroupBox("Recorder Information") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Name") {
                    CopyableValue(text: recorder.name, monospaced: true)
                }
                labeledRow("Role ARN") {
                    CopyableValue(text: recorder.roleARN, font: .caption, monospaced: true)
                }
                labeledRow("All Resources") {
                    Text(recorder.allSupported ? "Yes" : "No")
                }
                if !recorder.resourceTypes.isEmpty {
                    labeledRow("Resource Types") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(recorder.resourceTypes, id: \.self) { type in
                                Text(type)
                                    .font(.body.monospaced())
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                if let status {
                    labeledRow("Recording") {
                        HStack(spacing: 6) {
                            StatusBadge(text: status.recording ? "RECORDING" : "STOPPED", color: status.recording ? .green : .gray)
                            if !appState.isReadOnly {
                                Button(status.recording ? "Stop" : "Start") {
                                    toggleRecording()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                    if let time = status.lastStartTime {
                        labeledRow("Last Start") {
                            Text(time.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let time = status.lastStopTime {
                        labeledRow("Last Stop") {
                            Text(time.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !status.lastStatus.isEmpty {
                        labeledRow("Last Status") {
                            Text(status.lastStatus)
                                .font(.body.monospaced())
                        }
                    }
                    if let time = status.lastStatusChangeTime {
                        labeledRow("Status Changed") {
                            Text(time.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No status available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadStatus(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                let statuses = try await service.describeConfigurationRecorderStatus(names: [recorder.name])
                status = statuses.first
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }

    private func toggleRecording() {
        Task {
            do {
                if status?.recording == true {
                    try await service.stopConfigurationRecorder(name: recorder.name)
                } else {
                    try await service.startConfigurationRecorder(name: recorder.name)
                }
                loadStatus()
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
