import SwiftUI

struct LambdaInvokeView: View {
    @ObservedObject var service: LambdaService
    let function: LambdaFunction
    @Environment(\.dismiss) private var dismiss

    @State private var payload = "{}"
    @State private var invocationType = "RequestResponse"
    @State private var result: LambdaInvocationResult?
    @State private var isInvoking = false
    @State private var serviceError: ServiceError?

    private let invocationTypes = ["RequestResponse", "Event"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Function") {
                    LabeledContent("Name") {
                        Text(function.functionName)
                            .foregroundStyle(.secondary)
                    }
                    if !function.runtime.isEmpty {
                        LabeledContent("Runtime") {
                            Text(function.runtime)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Invocation") {
                    Picker("Type", selection: $invocationType) {
                        ForEach(invocationTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }

                Section {
                    CodeTextEditor(text: $payload, isEditable: true)
                        .frame(minHeight: 120)
                        .disableSmartSubstitutions()
                } header: {
                    HStack {
                        Text("Payload")
                        Spacer()
                        payloadTypeBadge
                    }
                }

                if let result {
                    responseSection(result)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Invoke") { invoke() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isInvoking)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 500)
        .serviceErrorAlert(error: $serviceError)
    }

    @ViewBuilder
    private var payloadTypeBadge: some View {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        if isJSON {
            Text("JSON")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        } else {
            Text("Text")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func responseSection(_ result: LambdaInvocationResult) -> some View {
        Section("Response") {
            HStack {
                Text("Status")
                Spacer()
                Text(result.isError ? "Error" : "Success")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((result.isError ? Color.red : Color.green).opacity(0.15), in: Capsule())
                    .foregroundStyle(result.isError ? .red : .green)
            }

            if let functionError = result.functionError {
                LabeledContent("Function Error") {
                    Text(functionError)
                        .foregroundStyle(.red)
                }
            }

            if let logResult = result.logResult, !logResult.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log Output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView([.horizontal, .vertical]) {
                        Text(logResult)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Payload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if result.isJSON {
                        Text("JSON")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    CopyButton(text: result.displayPayload)
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(result.displayPayload)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60)
            }
        }
    }

    private func invoke() {
        isInvoking = true
        result = nil
        Task {
            do {
                result = try await service.invokeFunction(
                    name: function.functionName,
                    payload: payload,
                    invocationType: invocationType
                )
            } catch {
                serviceError = error.asServiceError
            }
            isInvoking = false
        }
    }
}
