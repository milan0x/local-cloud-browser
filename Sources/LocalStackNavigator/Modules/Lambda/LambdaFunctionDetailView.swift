import SwiftUI

struct LambdaFunctionDetailView: View {
    @ObservedObject var service: LambdaService
    let function: LambdaFunction
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var showEditSheet = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            detailForm

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
        .sheet(isPresented: $showEditSheet) {
            LambdaCreateFunctionView(
                service: service,
                existingFunctionNames: [],
                editingFunction: function
            )
        }
    }

    @ViewBuilder
    private var detailForm: some View {
        Form {
            Section("Function Info") {
                LabeledContent("Name") {
                    CopyableValue(text: function.functionName)
                }
                if !function.functionArn.isEmpty {
                    LabeledContent("ARN") {
                        CopyableValue(text: function.functionArn, monospaced: true, allowsWrapping: true)
                    }
                }
                if !function.runtime.isEmpty {
                    LabeledContent("Runtime") {
                        StatusBadge(text: function.runtime, color: runtimeColor)
                    }
                }
                LabeledContent("Handler") {
                    CopyableValue(text: function.handler, monospaced: true)
                }
                LabeledContent("Role") {
                    CopyableValue(text: function.role, monospaced: true, allowsWrapping: true)
                }
                if !function.state.isEmpty {
                    LabeledContent("State") {
                        StatusBadge(text: function.state, color: stateColor)
                    }
                }
                if !function.description.isEmpty {
                    LabeledContent("Description") {
                        Text(function.description)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Configuration") {
                LabeledContent("Timeout") {
                    Text("\(function.timeout) seconds")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Memory") {
                    Text("\(function.memorySize) MB")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Code Size") {
                    Text(function.formattedCodeSize)
                        .foregroundStyle(.secondary)
                }
                if !function.codeSha256.isEmpty {
                    LabeledContent("Code SHA256") {
                        CopyableValue(text: function.codeSha256, monospaced: true)
                    }
                }
                if !function.version.isEmpty {
                    LabeledContent("Version") {
                        Text(function.version)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !function.lastModified.isEmpty {
                Section("Dates") {
                    LabeledContent("Last Modified") {
                        CopyableValue(text: function.lastModified)
                    }
                }
            }

            if !function.environment.isEmpty {
                Section("Environment Variables") {
                    ForEach(function.environment.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key) {
                            CopyableValue(text: value, monospaced: true)
                        }
                    }
                }
            }

            if !function.layers.isEmpty {
                Section("Layers") {
                    ForEach(function.layers, id: \.self) { layerArn in
                        CopyableValue(text: layerArn, monospaced: true, allowsWrapping: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runtimeColor: Color {
        switch function.runtimeBadgeColor {
        case .python: .blue
        case .nodejs: .green
        case .java: .orange
        case .dotnet: .purple
        case .ruby: .red
        case .custom: .gray
        }
    }

    private var stateColor: Color {
        function.isActive ? .green : .orange
    }
}
