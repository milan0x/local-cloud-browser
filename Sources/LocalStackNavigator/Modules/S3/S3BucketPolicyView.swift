import SwiftUI

struct S3BucketPolicyView: View {
    @ObservedObject var service: S3Service
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let bucket: String

    @State private var policyJSON = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bucket Policy — \(bucket)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    JSONInputSection(text: $policyJSON, config: .policyDocument)
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    if let successMessage {
                        Text(successMessage)
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Save") { savePolicy() }
                        .disabled(appState.isReadOnly || isSaving)
                }
                .padding()
            }
        }
        .frame(width: 520, height: 420)
        .task { loadPolicy() }
    }

    private func loadPolicy() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                policyJSON = try await service.getBucketPolicy(bucket: bucket)
            } catch let err as LocalStackClientError {
                if case .httpError(let code, _) = err, code == 404 {
                    policyJSON = ""
                } else {
                    errorMessage = err.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func savePolicy() {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        Task {
            do {
                try await service.putBucketPolicy(bucket: bucket, json: policyJSON)
                successMessage = "Policy saved."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
