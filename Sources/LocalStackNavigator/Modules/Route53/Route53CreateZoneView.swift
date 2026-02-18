import SwiftUI

struct Route53CreateZoneView: View {
    @ObservedObject var service: Route53Service
    @Environment(\.dismiss) private var dismiss
    @State private var zoneName = ""
    @State private var comment = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Domain Name", text: $zoneName)
                    .help("e.g. example.com")
                TextField("Comment (optional)", text: $comment)
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
        .frame(width: 420)
        .serviceErrorAlert(error: $serviceError)
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
                onCreate?(zoneName.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
