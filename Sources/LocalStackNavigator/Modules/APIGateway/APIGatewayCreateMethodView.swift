import SwiftUI

struct APIGatewayCreateMethodView: View {
    @ObservedObject var service: APIGatewayService
    let apiId: String
    let resourceId: String
    let resourcePath: String
    let existingMethods: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var httpMethod = "GET"
    @State private var authorizationType = "NONE"
    @State private var integrationType = "MOCK"
    @State private var integrationUri = ""
    @State private var integrationHttpMethod = "GET"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private static let httpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "ANY"]
    private static let authTypes = ["NONE", "AWS_IAM", "CUSTOM", "COGNITO_USER_POOLS"]
    private static let integrationTypes = ["MOCK", "HTTP", "HTTP_PROXY", "AWS_PROXY"]

    private var needsUri: Bool {
        integrationType == "HTTP" || integrationType == "HTTP_PROXY" || integrationType == "AWS_PROXY"
    }

    private var needsIntegrationMethod: Bool {
        integrationType == "HTTP" || integrationType == "HTTP_PROXY"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Method on \(resourcePath)") {
                    Picker("HTTP Method", selection: $httpMethod) {
                        ForEach(Self.httpMethods, id: \.self) { method in
                            Text(method).tag(method)
                        }
                    }

                    Picker("Authorization", selection: $authorizationType) {
                        ForEach(Self.authTypes, id: \.self) { auth in
                            Text(auth).tag(auth)
                        }
                    }
                }

                Section("Integration") {
                    Picker("Type", selection: $integrationType) {
                        ForEach(Self.integrationTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    if needsUri {
                        TextField("URI", text: $integrationUri)
                            .disableAutocorrection(true)
                    }

                    if needsIntegrationMethod {
                        Picker("Integration HTTP Method", selection: $integrationHttpMethod) {
                            ForEach(Self.httpMethods.filter({ $0 != "ANY" }), id: \.self) { method in
                                Text(method).tag(method)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if methodExists {
                Text("Method \(httpMethod) already exists on this resource.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

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
        .frame(width: 460)
        .frame(minHeight: 360)
        .serviceErrorAlert(error: $serviceError)
    }

    private var methodExists: Bool {
        existingMethods.contains(httpMethod)
    }

    private var isValid: Bool {
        if methodExists { return false }
        if needsUri && integrationUri.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                // Create method first
                try await service.putMethod(
                    apiId: apiId,
                    resourceId: resourceId,
                    httpMethod: httpMethod,
                    authorizationType: authorizationType
                )
                // Then attach integration
                try await service.putIntegration(
                    apiId: apiId,
                    resourceId: resourceId,
                    httpMethod: httpMethod,
                    type: integrationType,
                    uri: needsUri ? integrationUri.trimmingCharacters(in: .whitespaces) : "",
                    integrationHttpMethod: needsIntegrationMethod ? integrationHttpMethod : ""
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
