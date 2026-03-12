import SwiftUI

struct ACMImportCertificateView: View {
    @ObservedObject var service: ACMService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss

    @State private var certificate = ""
    @State private var privateKey = ""
    @State private var chain = ""
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Certificate PEM") {
                    TextEditor(text: $certificate)
                        .font(.body.monospaced())
                        .frame(height: 120)
                }
                Section("Private Key PEM") {
                    TextEditor(text: $privateKey)
                        .font(.body.monospaced())
                        .frame(height: 120)
                }
                Section("Certificate Chain PEM (optional)") {
                    TextEditor(text: $chain)
                        .font(.body.monospaced())
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let cert = certificate.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cert.isEmpty && !key.isEmpty
            && cert.hasPrefix("-----BEGIN")
            && key.hasPrefix("-----BEGIN")
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let arn = try await service.importCertificate(
                    cert: certificate.trimmingCharacters(in: .whitespacesAndNewlines),
                    key: privateKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    chain: chain.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                licenseManager.incrementCreateCount(for: .acm)
                onCreate?(arn)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
