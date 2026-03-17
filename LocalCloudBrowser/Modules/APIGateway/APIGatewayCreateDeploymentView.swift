import SwiftUI

struct APIGatewayCreateDeploymentView: View {
    @ObservedObject var service: APIGatewayService
    let apiId: String
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        CreateFormScaffold(
            minHeight: 180,
            isValid: true,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Deployment") {
                    TextField("Description (optional)", text: $description)
                }
        }
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createDeployment(
                    apiId: apiId,
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
