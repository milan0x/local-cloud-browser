import SwiftUI

struct RedshiftCreateClusterView: View {
    @ObservedObject var service: RedshiftService
    @Environment(\.dismiss) private var dismiss
    @State private var clusterIdentifier = ""
    @State private var masterUsername = "admin"
    @State private var masterPassword = ""
    @State private var nodeType = "dc2.large"
    @State private var numberOfNodes = 1
    @State private var dbName = "dev"
    @State private var portString = "5439"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var hasAttemptedCreate = false

    private let nodeTypes = [
        "dc2.large", "dc2.8xlarge",
        "ra3.xlplus", "ra3.4xlarge", "ra3.16xlarge",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Cluster Identifier", text: $clusterIdentifier)
                    .help("A unique identifier for the cluster (lowercase, alphanumeric, hyphens)")
                if hasAttemptedCreate && clusterIdentifier.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Cluster identifier is required.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("Master Username", text: $masterUsername)
                if hasAttemptedCreate && masterUsername.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Master username is required.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                SecureField("Master Password (min: 8)", text: $masterPassword)
                if hasAttemptedCreate && masterPassword.count < 8 {
                    Text("Password must be at least 8 characters.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Node Type", selection: $nodeType) {
                    ForEach(nodeTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }

                Stepper(value: $numberOfNodes, in: 1...10) {
                    HStack {
                        Text("Number of Nodes")
                        Spacer()
                        Text("\(numberOfNodes)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                TextField("Database Name", text: $dbName)
                    .help("Default: dev")

                TextField("Port", text: $portString)
                    .help("Default: 5439")
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    hasAttemptedCreate = true
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let id = clusterIdentifier.trimmingCharacters(in: .whitespaces)
        let user = masterUsername.trimmingCharacters(in: .whitespaces)
        return !id.isEmpty && !user.isEmpty && masterPassword.count >= 8
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createCluster(
                    id: clusterIdentifier.trimmingCharacters(in: .whitespaces),
                    masterUsername: masterUsername.trimmingCharacters(in: .whitespaces),
                    masterPassword: masterPassword,
                    nodeType: nodeType,
                    numberOfNodes: numberOfNodes,
                    dbName: dbName.trimmingCharacters(in: .whitespaces),
                    port: Int(portString) ?? 5439
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
