import SwiftUI

struct SSMParameterValuePaneView: View {
    @ObservedObject var service: SSMService
    let parameter: SSMParameter
    @ObservedObject var toolbarState: SSMToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var parameterValue: SSMParameterValue?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isValueRevealed = false
    @State private var showDetailSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && parameterValue == nil {
                ProgressView("Loading parameter value...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, parameterValue == nil {
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
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showDetailSheet && !isLoading else { return }
            loadValue(silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard toolbarState.pendingAction == .viewDetails else { return }
            toolbarState.pendingAction = nil
            showDetailSheet = true
        }
        .sheet(isPresented: $showDetailSheet) {
            SSMParameterDetailView(service: service, parameter: parameter)
        }
    }

    @ViewBuilder
    private var valueContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parameter.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    HStack(spacing: 6) {
                        StatusBadge(text: parameter.displayType, color: typeColor(parameter.type))
                        if let desc = parameter.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if parameter.isSecureString {
                    Button {
                        isValueRevealed.toggle()
                    } label: {
                        Image(systemName: isValueRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isValueRevealed ? "Hide Value" : "Reveal Value")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Value area
            if parameter.isSecureString && !isValueRevealed {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("SecureString value is hidden")
                        .foregroundStyle(.secondary)
                    Button("Reveal") {
                        isValueRevealed = true
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let pv = parameterValue {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        if pv.isJSON {
                            StatusBadge(text: "JSON", color: .blue)
                        } else {
                            StatusBadge(text: "Text", color: .gray)
                        }
                        Spacer()
                        CopyButton(text: pv.displayValue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ScrollView([.horizontal, .vertical]) {
                        Text(pv.displayValue)
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

            // Status bar
            Divider()
            HStack {
                if let pv = parameterValue {
                    StatusBadge(text: "v\(pv.version)", color: .blue)
                }
                Spacer()
                if let pv = parameterValue {
                    Text(SQSMessage.formattedSize(pv.value.utf8.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "SecureString": .orange
        case "StringList": .purple
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
                let value = try await service.getParameter(name: parameter.name)
                parameterValue = value
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
