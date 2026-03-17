import SwiftUI

struct Route53ResolverCreateEndpointView: View {
    @ObservedObject var service: Route53ResolverService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var direction = "INBOUND"
    @State private var securityGroupId = "sg-default"
    @State private var subnetId = "subnet-default"
    @State private var ip = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var onCreate: ((String) -> Void)? = nil

    private let directions = ["INBOUND", "OUTBOUND"]

    var body: some View {
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Endpoint Name", text: $name)

                Picker("Direction", selection: $direction) {
                    ForEach(directions, id: \.self) { d in
                        Text(d).tag(d)
                    }
                }

                Section("Network") {
                    TextField("Security Group ID", text: $securityGroupId)
                    TextField("Subnet ID", text: $subnetId)
                    TextField("IP Address (optional)", text: $ip)
                }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !securityGroupId.trimmingCharacters(in: .whitespaces).isEmpty &&
        !subnetId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let trimmedIp = ip.trimmingCharacters(in: .whitespaces)
                try await service.createResolverEndpoint(
                    name: name.trimmingCharacters(in: .whitespaces),
                    direction: direction,
                    securityGroupIds: [securityGroupId.trimmingCharacters(in: .whitespaces)],
                    ipAddresses: [(subnetId: subnetId.trimmingCharacters(in: .whitespaces), ip: trimmedIp.isEmpty ? nil : trimmedIp)]
                )
                licenseManager.incrementCreateCount(for: .route53)
                onCreate?(name.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
