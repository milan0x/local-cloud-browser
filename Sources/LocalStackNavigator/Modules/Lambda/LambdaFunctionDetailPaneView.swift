import SwiftUI

struct LambdaFunctionDetailPaneView: View {
    @ObservedObject var service: LambdaService
    let function: LambdaFunction
    @ObservedObject var toolbarState: LambdaToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var showDetailSheet = false
    @State private var showInvokeSheet = false

    var body: some View {
        VStack(spacing: 0) {
            detailContent
        }
        .onChange(of: toolbarState.pendingAction) {
            switch toolbarState.pendingAction {
            case .viewDetails:
                toolbarState.pendingAction = nil
                showDetailSheet = true
            case .invoke:
                toolbarState.pendingAction = nil
                showInvokeSheet = true
            default:
                break
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            LambdaFunctionDetailView(service: service, function: function)
        }
        .sheet(isPresented: $showInvokeSheet) {
            LambdaInvokeView(service: service, function: function)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(function.functionName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    HStack(spacing: 6) {
                        if !function.runtime.isEmpty {
                            StatusBadge(text: function.runtime, color: runtimeColor)
                        }
                        if !function.state.isEmpty {
                            StatusBadge(text: function.state, color: stateColor)
                        }
                        if !function.description.isEmpty {
                            Text(function.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Configuration section
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    configSection
                    if !function.environment.isEmpty {
                        environmentSection
                    }
                    codeInfoSection
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Status bar
            Divider()
            HStack {
                if !function.functionArn.isEmpty {
                    Text(function.functionArn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !function.lastModified.isEmpty {
                    Text(function.lastModified)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Handler")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(function.handler)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Timeout")
                        .foregroundStyle(.secondary)
                    Text("\(function.timeout)s")
                }
                GridRow {
                    Text("Memory")
                        .foregroundStyle(.secondary)
                    Text("\(function.memorySize) MB")
                }
                GridRow {
                    Text("Role")
                        .foregroundStyle(.secondary)
                    Text(function.role)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Environment Variables")
                .font(.headline)
            ForEach(function.environment.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.body.monospaced())
                        .fontWeight(.medium)
                    Text("=")
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    CopyButton(text: "\(key)=\(value)")
                }
            }
        }
    }

    private var codeInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Code")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Size")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(function.formattedCodeSize)
                }
                if !function.codeSha256.isEmpty {
                    GridRow {
                        Text("SHA256")
                            .foregroundStyle(.secondary)
                        Text(function.codeSha256)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
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
