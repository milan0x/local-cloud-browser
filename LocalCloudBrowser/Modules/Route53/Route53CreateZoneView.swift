import SwiftUI

struct Route53CreateZoneView: View {
    @ObservedObject var service: Route53Service
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var zoneName = ""
    @State private var comment = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            width: 420,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Domain Name", text: $zoneName)
                    .help("e.g. example.com")
                TextField("Comment (optional)", text: $comment)
        }
    }

    private var isValid: Bool {
        !zoneName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                _ = try await service.createHostedZone(
                    name: zoneName.trimmingCharacters(in: .whitespaces),
                    comment: comment.trimmingCharacters(in: .whitespaces)
                )
                licenseManager.incrementCreateCount(for: .route53)
                onCreate?(zoneName.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
