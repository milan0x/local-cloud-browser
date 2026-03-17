import SwiftUI

struct APIGatewayCreateStageView: View {
    @ObservedObject var service: APIGatewayService
    let apiId: String
    let deployments: [APIDeployment]
    let existingStageNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var stageName = ""
    @State private var deploymentId = ""
    @State private var description = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private static let namePattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_]+$")

    var body: some View {
        CreateFormScaffold(
            width: 420,
            minHeight: 300,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Stage") {
                    TextField("Stage Name", text: $stageName)
                        .disableAutocorrection(true)
                    TextField("Description (optional)", text: $description)
                }

                Section("Deployment") {
                    Picker("Deployment", selection: $deploymentId) {
                        Text("Select a deployment").tag("")
                        ForEach(deployments) { deployment in
                            HStack {
                                Text(deployment.id)
                                if !deployment.description.isEmpty {
                                    Text("— \(deployment.description)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(deployment.id)
                        }
                    }
                }

            if nameExists {
                Text("A stage named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameIsValid {
                Text("Stage name can only contain letters, numbers, and underscores.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            if let first = deployments.first {
                deploymentId = first.id
            }
        }
    }

    private var trimmedName: String {
        stageName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingStageNames.contains(trimmedName)
    }

    private var nameIsValid: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists && nameIsValid && !deploymentId.isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createStage(
                    apiId: apiId,
                    stageName: trimmedName,
                    deploymentId: deploymentId,
                    description: description.trimmingCharacters(in: .whitespaces)
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
