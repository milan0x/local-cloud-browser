import SwiftUI

struct SecretValuePaneView: View {
    @ObservedObject var service: SecretsManagerService
    let secret: Secret
    @ObservedObject var toolbarState: SecretsManagerToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var secretValue: SecretValue?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isValueRevealed = false
    @State private var showDetailSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && secretValue == nil {
                ProgressView("Loading secret value...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, secretValue == nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadValue() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                valueContent
            }
        }
        .task { loadValue() }
        .onAutoRefresh(canRefresh: { !showDetailSheet && !isLoading }) {
            loadValue(silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard toolbarState.pendingAction == .viewDetails else { return }
            toolbarState.pendingAction = nil
            showDetailSheet = true
        }
        .sheet(isPresented: $showDetailSheet) {
            SecretDetailView(service: service, secret: secret)
        }
    }

    @ViewBuilder
    private var valueContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(secret.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    if let desc = secret.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    isValueRevealed.toggle()
                } label: {
                    Image(systemName: isValueRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isValueRevealed ? "Hide Value" : "Reveal Value")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Value area
            if isValueRevealed {
                if let sv = secretValue {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            if sv.isJSON {
                                StatusBadge(text: "JSON", color: .blue)
                            } else {
                                StatusBadge(text: "Text", color: .gray)
                            }
                            if !sv.versionId.isEmpty {
                                Text("v: \(String(sv.versionId.prefix(8)))...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            CopyButton(text: sv.displayValue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        ScrollView([.horizontal, .vertical]) {
                            Text(sv.displayValue)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("No value available")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Secret value is hidden")
                        .foregroundStyle(.secondary)
                    Button("Reveal") {
                        isValueRevealed = true
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Status bar
            Divider()
            HStack {
                if let sv = secretValue {
                    if !sv.versionStages.isEmpty {
                        ForEach(sv.versionStages, id: \.self) { stage in
                            StatusBadge(text: stage, color: stageColor(stage))
                        }
                    }
                }
                Spacer()
                if let sv = secretValue, let size = sv.secretString?.utf8.count {
                    Text(SQSMessage.formattedSize(size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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

    private func loadValue(silent: Bool = false) {
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let value = try await service.getSecretValue(secretId: secret.arn)
                secretValue = value
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
            }
        }
    }
}
