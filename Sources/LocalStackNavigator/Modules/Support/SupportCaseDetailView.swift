import SwiftUI
import AppKit

struct SupportCaseDetailView: View {
    @ObservedObject var service: SupportService
    let supportCase: SupportCase
    @EnvironmentObject private var appState: AppState

    @State private var detail: SupportCaseDetail?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && detail == nil {
                ProgressView("Loading case details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        if let detail, !detail.communications.isEmpty {
                            communicationsSection(detail.communications)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task { loadDetails() }
        .onChange(of: supportCase.caseId) {
            detail = nil
            loadDetails()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !isLoading else { return }
            loadDetails(silent: true)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Subject") {
                    CopyableValue(text: supportCase.subject)
                }
                labeledRow("Case ID") {
                    CopyableValue(text: supportCase.caseId, font: .caption, monospaced: true)
                }
                if !supportCase.displayId.isEmpty {
                    labeledRow("Display ID") {
                        CopyableValue(text: supportCase.displayId, font: .caption, monospaced: true)
                    }
                }
                labeledRow("Status") {
                    Text(supportCase.statusDisplayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(supportCase.statusBadgeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(supportCase.statusBadgeColor)
                }
                if !supportCase.severityCode.isEmpty {
                    labeledRow("Severity") {
                        Text(supportCase.severityCode.capitalized)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(supportCase.severityBadgeColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(supportCase.severityBadgeColor)
                    }
                }
                if !supportCase.serviceCode.isEmpty {
                    labeledRow("Service") {
                        Text(supportCase.serviceCode)
                            .textSelection(.enabled)
                    }
                }
                if !supportCase.categoryCode.isEmpty {
                    labeledRow("Category") {
                        Text(supportCase.categoryCode)
                            .textSelection(.enabled)
                    }
                }
                if !supportCase.submittedBy.isEmpty {
                    labeledRow("Submitted By") {
                        Text(supportCase.submittedBy)
                            .textSelection(.enabled)
                    }
                }
                if let date = supportCase.timeCreatedDate {
                    labeledRow("Created") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                if !supportCase.language.isEmpty {
                    labeledRow("Language") {
                        Text(supportCase.language)
                    }
                }
                if !supportCase.ccEmailAddresses.isEmpty {
                    labeledRow("CC Emails") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(supportCase.ccEmailAddresses, id: \.self) { email in
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Spacer()
                    Button {
                        let cli = supportCase.describeCaseCLI(endpointUrl: appState.endpoint, region: appState.region)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cli, forType: .string)
                    } label: {
                        Label("Copy CLI", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Communications Section

    private func communicationsSection(_ communications: [SupportCommunication]) -> some View {
        GroupBox("Communications") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(communications) { comm in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if !comm.submittedBy.isEmpty {
                                Text(comm.submittedBy)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                            if let date = comm.timeCreatedDate {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(comm.body)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
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
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadDetails(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                let loaded = try await service.describeCaseDetail(caseId: supportCase.caseId)
                detail = loaded
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }
}
