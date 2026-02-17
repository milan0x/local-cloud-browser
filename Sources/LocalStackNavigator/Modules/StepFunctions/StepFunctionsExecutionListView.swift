import SwiftUI
import AppKit

struct StepFunctionsExecutionListView: View {
    @ObservedObject var service: StepFunctionsService
    let stateMachine: StateMachineSummary
    @EnvironmentObject private var appState: AppState

    @State private var executions: [StepFunctionsExecution] = []
    @State private var activeExecution: StepFunctionsExecution?
    @State private var executionDetail: StepFunctionsExecutionDetail?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?
    @State private var showStartSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if let execution = activeExecution {
                executionDetailView(execution)
            } else {
                executionListView
            }
        }
        .sheet(isPresented: $showStartSheet) {
            StepFunctionsStartExecutionView(
                service: service,
                stateMachineArn: stateMachine.stateMachineArn
            )
            .onDisappear { loadExecutions(force: true) }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadExecutions() }
        .onChange(of: stateMachine.stateMachineArn) {
            executions = []
            activeExecution = nil
            executionDetail = nil
            loadExecutions()
        }
        .onAutoRefresh(canRefresh: { !showStartSheet && !isLoading }) {
            if activeExecution != nil {
                loadExecutionDetail(silent: true)
            } else {
                loadExecutions(force: true, silent: true)
            }
        }
    }

    // MARK: - Execution List

    private var executionListView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(stateMachine.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    showStartSheet = true
                } label: {
                    Label("Start Execution", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ListLoadingContent(isLoading: isLoading, isEmpty: executions.isEmpty, errorMessage: nil, loadingMessage: "Loading executions...", onRetry: {}) {
                if executions.isEmpty {
                    EmptyStateView(icon: "play.slash", message: "No executions")
                } else {
                    List {
                        ForEach(executions) { execution in
                            Button {
                                activeExecution = execution
                                loadExecutionDetail()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(execution.displayName)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        if let start = execution.startDate {
                                            Text(start.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if let duration = execution.duration {
                                        Text(duration)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    executionStatusBadge(execution.status)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Copy Execution ARN") {
                                    copyToClipboard(execution.executionArn)
                                }
                                Button("Copy as AWS CLI") {
                                    copyToClipboard(execution.describeExecutionCLI(
                                        endpointUrl: appState.endpoint, region: appState.region
                                    ))
                                }
                                if execution.status == "RUNNING" {
                                    Divider()
                                    Button("Stop Execution", role: .destructive) {
                                        stopExecution(execution)
                                    }
                                    .disabled(appState.isReadOnly)
                                }
                            }
                        }
                    }

                    Divider()
                    HStack {
                        Text("\(executions.count) execution\(executions.count == 1 ? "" : "s")")
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

    // MARK: - Execution Detail (drill-down)

    private func executionDetailView(_ execution: StepFunctionsExecution) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    activeExecution = nil
                    executionDetail = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Executions")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(execution.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if execution.status == "RUNNING" {
                    Button {
                        stopExecution(execution)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.isReadOnly)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let detail = executionDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        executionInfoBar(detail)
                        executionIOSection(detail)
                        StepFunctionsExecutionHistoryView(
                            service: service,
                            executionArn: execution.executionArn
                        )
                    }
                    .padding(16)
                }
            } else {
                ProgressView("Loading execution details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func executionInfoBar(_ detail: StepFunctionsExecutionDetail) -> some View {
        HStack(spacing: 10) {
            executionStatusBadge(detail.status)

            if let duration = detail.duration {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(duration)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if let start = detail.startDate {
                Text("Started: \(start.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let stop = detail.stopDate {
                Text("Stopped: \(stop.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func executionIOSection(_ detail: StepFunctionsExecutionDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !detail.input.isEmpty {
                DisclosureGroup("Input") {
                    Text(detail.prettyInput)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if !detail.output.isEmpty {
                DisclosureGroup("Output") {
                    Text(detail.prettyOutput)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Badges

    private func executionStatusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: executionStatusColor(status))
    }

    private func executionStatusColor(_ status: String) -> Color {
        switch status {
        case "RUNNING": .blue
        case "SUCCEEDED": .green
        case "FAILED": .red
        case "TIMED_OUT": .orange
        case "ABORTED": .gray
        default: .gray
        }
    }

    // MARK: - Data

    private func loadExecutions(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !silent { isLoading = true }
        Task {
            do {
                let loaded = try await service.listExecutions(stateMachineArn: stateMachine.stateMachineArn)
                if executions != loaded {
                    executions = loaded
                }
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }

    private func loadExecutionDetail(silent: Bool = false) {
        guard let execution = activeExecution else { return }
        Task {
            do {
                executionDetail = try await service.describeExecution(arn: execution.executionArn)
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
        }
    }

    private func stopExecution(_ execution: StepFunctionsExecution) {
        Task {
            do {
                try await service.stopExecution(arn: execution.executionArn, cause: nil, error: nil)
                loadExecutions(force: true)
                if activeExecution?.executionArn == execution.executionArn {
                    loadExecutionDetail()
                }
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
