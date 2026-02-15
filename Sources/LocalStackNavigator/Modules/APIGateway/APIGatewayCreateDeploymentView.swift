import SwiftUI

struct APIGatewayCreateDeploymentView: View {
    @ObservedObject var service: APIGatewayService
    let apiId: String
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Deployment") {
                    TextField("Description (optional)", text: $description)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(width: 380)
        .frame(minHeight: 180)
        .serviceErrorAlert(error: $serviceError)
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
