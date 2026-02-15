import SwiftUI

struct SecretDetailView: View {
    @ObservedObject var service: SecretsManagerService
    let secret: Secret
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var detail: SecretDetail?
    @State private var secretValue: SecretValue?
    @State private var isLoadingDetail = false
    @State private var isLoadingValue = false
    @State private var loadError: String?
    @State private var isValueRevealed = false
    @State private var showEditSheet = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if isLoadingDetail && detail == nil {
                ProgressView("Loading secret details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadDetail() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                detailForm(detail)
            }

            Divider()

            HStack {
                Spacer()
                if !appState.isReadOnly {
                    Button("Edit") { showEditSheet = true }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 500)
        .task { loadDetail() }
        .sheet(isPresented: $showEditSheet) {
            CreateSecretView(
                service: service,
                existingSecretNames: [],
                editingSecret: secret,
                editingValue: secretValue?.displayValue ?? ""
            )
            .onDisappear {
                loadDetail()
            }
        }
    }

    @ViewBuilder
    private func detailForm(_ detail: SecretDetail) -> some View {
        Form {
            Section("Secret Info") {
                LabeledContent("Name") {
                    CopyableValue(text: secret.name)
                }
                LabeledContent("ARN") {
                    CopyableValue(text: detail.arn, monospaced: true, allowsWrapping: true)
                }
                if let desc = detail.description, !desc.isEmpty {
                    LabeledContent("Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Dates") {
                if let created = detail.createdDate {
                    LabeledContent("Created") {
                        CopyableValue(text: Self.dateFormatter.string(from: created))
                    }
                }
                if let changed = detail.lastChangedDate {
                    LabeledContent("Last Changed") {
                        CopyableValue(text: Self.dateFormatter.string(from: changed))
                    }
                }
                if let accessed = detail.lastAccessedDate {
                    LabeledContent("Last Accessed") {
                        CopyableValue(text: Self.dateFormatter.string(from: accessed))
                    }
                }
            }

            secretValueSection

            if !detail.versionIdsToStages.isEmpty {
                Section("Versions") {
                    ForEach(detail.versionIdsToStages.sorted(by: { $0.key < $1.key }), id: \.key) { versionId, stages in
                        LabeledContent(versionId.prefix(8) + "...") {
                            HStack(spacing: 4) {
                                ForEach(stages, id: \.self) { stage in
                                    StatusBadge(text: stage, color: stageColor(stage))
                                }
                            }
                        }
                    }
                }
            }

            if !detail.tags.isEmpty {
                Section("Tags") {
                    ForEach(detail.tags.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key) {
                            CopyableValue(text: value)
                        }
                    }
                }
            }

            if detail.rotationEnabled {
                Section("Rotation") {
                    LabeledContent("Rotation Enabled") {
                        Text("Yes")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var secretValueSection: some View {
        Section {
            if isLoadingValue {
                ProgressView("Loading value...")
            } else if let sv = secretValue {
                if isValueRevealed {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if sv.isJSON {
                                StatusBadge(text: "JSON", color: .blue)
                            }
                            Spacer()
                            CopyButton(text: sv.displayValue)
                        }
                        Text(sv.displayValue)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(String(repeating: "\u{2022}", count: 24))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No value available")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Secret Value")
                Spacer()
                Button {
                    if !isValueRevealed && secretValue == nil {
                        loadSecretValue()
                    }
                    isValueRevealed.toggle()
                } label: {
                    Image(systemName: isValueRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isValueRevealed ? "Hide Value" : "Reveal Value")
            }
        }
    }

    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "AWSCURRENT": .green
        case "AWSPREVIOUS": .orange
        default: .gray
        }
    }

    // MARK: - Data

    private func loadDetail() {
        isLoadingDetail = true
        loadError = nil
        Task {
            do {
                detail = try await service.describeSecret(secretId: secret.arn)
                if isValueRevealed {
                    await loadSecretValueAsync()
                }
            } catch {
                loadError = error.localizedDescription
            }
            isLoadingDetail = false
        }
    }

    private func loadSecretValue() {
        isLoadingValue = true
        Task {
            await loadSecretValueAsync()
            isLoadingValue = false
        }
    }

    private func loadSecretValueAsync() async {
        do {
            secretValue = try await service.getSecretValue(secretId: secret.arn)
        } catch {
            Log.warn("Failed to load secret value: \(error.localizedDescription)", category: "SecretsManager")
        }
    }
}
