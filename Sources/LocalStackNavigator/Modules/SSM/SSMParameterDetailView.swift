import SwiftUI

struct SSMParameterDetailView: View {
    @ObservedObject var service: SSMService
    let parameter: SSMParameter
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var parameterValue: SSMParameterValue?
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
            if isLoadingValue && parameterValue == nil {
                ProgressView("Loading parameter details...")
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
            } else {
                detailForm
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
            SSMCreateParameterView(
                service: service,
                existingParameterNames: [],
                editingParameter: parameter,
                editingValue: parameterValue?.value ?? ""
            )
            .onDisappear {
                loadDetail()
            }
        }
    }

    @ViewBuilder
    private var detailForm: some View {
        Form {
            Section("Parameter Info") {
                LabeledContent("Name") {
                    CopyableValue(text: parameter.name)
                }
                if let arn = parameter.arn {
                    LabeledContent("ARN") {
                        CopyableValue(text: arn, monospaced: true, allowsWrapping: true)
                    }
                }
                LabeledContent("Type") {
                    Text(parameter.displayType)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(typeColor(parameter.type).opacity(0.15), in: Capsule())
                        .foregroundStyle(typeColor(parameter.type))
                }
                LabeledContent("Version") {
                    Text("\(parameter.version)")
                        .foregroundStyle(.secondary)
                }
                if let desc = parameter.description, !desc.isEmpty {
                    LabeledContent("Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }
                if let tier = parameter.tier {
                    LabeledContent("Tier") {
                        Text(tier)
                            .foregroundStyle(.secondary)
                    }
                }
                if let dataType = parameter.dataType {
                    LabeledContent("Data Type") {
                        Text(dataType)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let lastModified = parameter.lastModifiedDate {
                Section("Dates") {
                    LabeledContent("Last Modified") {
                        CopyableValue(text: Self.dateFormatter.string(from: lastModified))
                    }
                }
            }

            parameterValueSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var parameterValueSection: some View {
        Section {
            if isLoadingValue {
                ProgressView("Loading value...")
            } else if let pv = parameterValue {
                if parameter.isSecureString && !isValueRevealed {
                    Text(String(repeating: "\u{2022}", count: 24))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if pv.isJSON {
                                Text("JSON")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            CopyButton(text: pv.displayValue)
                        }
                        Text(pv.displayValue)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("No value available")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Parameter Value")
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

    private func loadDetail() {
        isLoadingValue = true
        loadError = nil
        Task {
            do {
                parameterValue = try await service.getParameter(name: parameter.name)
            } catch {
                loadError = error.localizedDescription
            }
            isLoadingValue = false
        }
    }
}
