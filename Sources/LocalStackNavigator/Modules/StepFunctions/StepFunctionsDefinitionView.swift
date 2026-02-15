import SwiftUI

struct StepFunctionsDefinitionView: View {
    @ObservedObject var service: StepFunctionsService
    let stateMachineArn: String
    @EnvironmentObject private var appState: AppState

    @State private var detail: StateMachineDetail?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && detail == nil {
                ProgressView("Loading definition...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                VStack(spacing: 0) {
                    infoBar(detail)
                    Divider()
                    CodeTextEditor(text: .constant(detail.prettyDefinition), isEditable: false)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No definition available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadDetail() }
        .onChange(of: stateMachineArn) {
            detail = nil
            loadDetail()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !isLoading else { return }
            loadDetail(silent: true)
        }
    }

    private func infoBar(_ detail: StateMachineDetail) -> some View {
        HStack(spacing: 10) {
            statusBadge(detail.status)
            typeBadge(detail.type)

            if !detail.roleArn.isEmpty {
                HStack(spacing: 4) {
                    Text("Role:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(detail.roleArn)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if let date = detail.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: statusColor(status))
    }

    private func typeBadge(_ type: String) -> some View {
        StatusBadge(text: type, color: typeColor(type))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ACTIVE": .green
        case "DELETING": .red
        default: .gray
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "STANDARD": .blue
        case "EXPRESS": .purple
        default: .gray
        }
    }

    private func loadDetail(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                detail = try await service.describeStateMachine(arn: stateMachineArn)
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }
}
