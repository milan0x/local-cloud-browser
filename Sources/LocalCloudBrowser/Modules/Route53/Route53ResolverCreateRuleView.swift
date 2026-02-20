import SwiftUI

struct Route53ResolverCreateRuleView: View {
    @ObservedObject var service: Route53ResolverService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ruleType = "FORWARD"
    @State private var domainName = ""
    @State private var resolverEndpointId = ""
    @State private var targetIp = ""
    @State private var targetPort = 53
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let ruleTypes = ["FORWARD", "SYSTEM", "RECURSIVE"]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Rule Name", text: $name)

                Picker("Rule Type", selection: $ruleType) {
                    ForEach(ruleTypes, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }

                TextField("Domain Name", text: $domainName)

                if ruleType == "FORWARD" {
                    Section("Forwarding") {
                        TextField("Resolver Endpoint ID (optional)", text: $resolverEndpointId)
                            .textFieldStyle(.roundedBorder)
                        TextField("Target IP", text: $targetIp)
                            .textFieldStyle(.roundedBorder)
                        Stepper("Target Port: \(targetPort)", value: $targetPort, in: 1...65535)
                    }
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
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 450)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !domainName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let trimmedIp = targetIp.trimmingCharacters(in: .whitespaces)
                let targets: [(ip: String, port: Int)] = trimmedIp.isEmpty ? [] : [(ip: trimmedIp, port: targetPort)]
                let trimmedEndpointId = resolverEndpointId.trimmingCharacters(in: .whitespaces)
                try await service.createResolverRule(
                    name: name.trimmingCharacters(in: .whitespaces),
                    ruleType: ruleType,
                    domainName: domainName.trimmingCharacters(in: .whitespaces),
                    resolverEndpointId: trimmedEndpointId.isEmpty ? nil : trimmedEndpointId,
                    targetIps: targets
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
