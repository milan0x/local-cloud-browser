import SwiftUI

struct CloudFormationStackDetailView: View {
    @ObservedObject var service: CloudFormationService
    let stackName: String
    @Environment(\.dismiss) private var dismiss

    @State private var detail: CloudFormationStackDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading stack details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                detailForm(detail)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 580)
        .frame(minHeight: 300)
        .task { loadDetail() }
    }

    @ViewBuilder
    private func detailForm(_ detail: CloudFormationStackDetail) -> some View {
        Form {
            Section("Stack Info") {
                LabeledContent("Name") {
                    CopyableValue(text: detail.stackName)
                }
                LabeledContent("Stack ID") {
                    CopyableValue(text: detail.stackId, monospaced: true, allowsWrapping: true)
                }
                LabeledContent("Status") {
                    Text(detail.stackStatus)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            detail.statusColor.swiftUIColor.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(detail.statusColor.swiftUIColor)
                }
                if let desc = detail.templateDescription, !desc.isEmpty {
                    LabeledContent("Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if detail.creationTime != nil || detail.lastUpdatedTime != nil {
                Section("Dates") {
                    if let created = detail.creationTime {
                        LabeledContent("Created") {
                            CopyableValue(text: Self.dateFormatter.string(from: created))
                        }
                    }
                    if let updated = detail.lastUpdatedTime {
                        LabeledContent("Last Updated") {
                            CopyableValue(text: Self.dateFormatter.string(from: updated))
                        }
                    }
                }
            }

            if !detail.capabilities.isEmpty {
                Section("Capabilities") {
                    ForEach(detail.capabilities, id: \.self) { cap in
                        Text(cap)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let roleARN = detail.roleARN, !roleARN.isEmpty {
                Section("Role") {
                    LabeledContent("Role ARN") {
                        CopyableValue(text: roleARN, monospaced: true, allowsWrapping: true)
                    }
                }
            }

            if !detail.parameters.isEmpty {
                Section("Parameters") {
                    ForEach(detail.parameters) { param in
                        LabeledContent(param.parameterKey) {
                            CopyableValue(text: param.parameterValue, monospaced: true)
                        }
                    }
                }
            }

            if !detail.outputs.isEmpty {
                Section("Outputs") {
                    ForEach(detail.outputs) { output in
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(output.outputKey) {
                                CopyableValue(text: output.outputValue, monospaced: true)
                            }
                            if let desc = output.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func loadDetail() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                detail = try await service.describeStack(name: stackName)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
