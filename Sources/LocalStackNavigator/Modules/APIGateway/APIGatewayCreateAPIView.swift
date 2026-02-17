import SwiftUI

struct APIGatewayCreateAPIView: View {
    @ObservedObject var service: APIGatewayService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var endpointType = "REGIONAL"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingAPINames: Set<String>

    private static let endpointTypes = ["REGIONAL", "EDGE", "PRIVATE"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("REST API") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                }

                Section("Endpoint") {
                    Picker("Endpoint Type", selection: $endpointType) {
                        ForEach(Self.endpointTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("An API named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 420)
        .frame(minHeight: 280)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingAPINames.contains(trimmedName)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createRestApi(
                    name: trimmedName,
                    description: description.trimmingCharacters(in: .whitespaces),
                    endpointType: endpointType
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
