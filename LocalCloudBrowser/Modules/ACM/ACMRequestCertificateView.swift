import SwiftUI

struct ACMRequestCertificateView: View {
    @ObservedObject var service: ACMService
    @Environment(\.dismiss) private var dismiss

    @State private var domain = ""
    @State private var sans = ""
    @State private var keyAlgorithm = "RSA_2048"
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    var onCreate: ((String) -> Void)? = nil

    private let keyAlgorithms = ["RSA_2048", "EC_prime256v1", "EC_secp384r1"]

    var body: some View {
        CreateFormScaffold(
            width: 420,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: "Request",
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Domain Name", text: $domain)
                    .help("Primary domain (e.g., example.com or *.example.com)")
                TextField("Subject Alternative Names", text: $sans)
                    .help("Comma-separated additional domains (optional)")
                Picker("Key Algorithm", selection: $keyAlgorithm) {
                    ForEach(keyAlgorithms, id: \.self) { algo in
                        Text(algo).tag(algo)
                    }
                }
        }
    }

    private var isValid: Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.contains(".")
    }

    private func save() {
        isSaving = true
        serviceError = nil
        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        let sansList = sans
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Task {
            do {
                _ = try await service.requestCertificate(
                    domain: trimmedDomain,
                    sans: sansList,
                    keyAlgorithm: keyAlgorithm
                )
                onCreate?(trimmedDomain)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
