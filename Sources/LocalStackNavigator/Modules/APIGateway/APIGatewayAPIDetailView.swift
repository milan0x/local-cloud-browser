import SwiftUI

struct APIGatewayAPIDetailView: View {
    let api: RestApi
    let endpoint: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("REST API") {
                    LabeledContent("Name") {
                        CopyableValue(text: api.name)
                    }
                    LabeledContent("ID") {
                        CopyableValue(text: api.id, monospaced: true)
                    }
                    if !api.description.isEmpty {
                        LabeledContent("Description") {
                            Text(api.description)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Configuration") {
                    LabeledContent("Endpoint Type") {
                        Text(api.endpointType)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if !api.apiKeySource.isEmpty {
                        LabeledContent("API Key Source") {
                            Text(api.apiKeySource)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !api.version.isEmpty {
                        LabeledContent("Version") {
                            Text(api.version)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !api.createdDate.isEmpty {
                    Section("Dates") {
                        LabeledContent("Created") {
                            CopyableValue(text: api.createdDate)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: 300)
    }
}
