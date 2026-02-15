import SwiftUI

struct TranscribeCreateJobView: View {
    @ObservedObject var service: TranscribeService
    @Environment(\.dismiss) private var dismiss

    @State private var jobName = ""
    @State private var mediaUri = ""
    @State private var languageCode = "en-US"
    @State private var mediaFormat = "wav"
    @State private var outputBucketName = ""
    @State private var isSaving = false
    @State private var serviceError: ServiceError?
    @State private var hasAttemptedCreate = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Job Name", text: $jobName)
                    if hasAttemptedCreate && jobName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Job name is required")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Media File URI", text: $mediaUri, prompt: Text("s3://bucket/key.wav"))
                    if hasAttemptedCreate && !isMediaUriValid {
                        Text("Media URI must start with s3://")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Language", selection: $languageCode) {
                        ForEach(TranscriptionJob.supportedLanguages, id: \.code) { lang in
                            Text("\(lang.name) (\(lang.code))").tag(lang.code)
                        }
                    }

                    Picker("Media Format", selection: $mediaFormat) {
                        ForEach(TranscriptionJob.supportedMediaFormats, id: \.self) { format in
                            Text(format.uppercased()).tag(format)
                        }
                    }
                }

                Section {
                    TextField("Output Bucket Name (optional)", text: $outputBucketName)
                    Text("If empty, output is stored in a service-managed bucket")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start Job") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 480)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isMediaUriValid: Bool {
        let uri = mediaUri.trimmingCharacters(in: .whitespaces)
        return uri.hasPrefix("s3://") && uri.count > 5
    }

    private var isValid: Bool {
        let name = jobName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && isMediaUriValid
    }

    private func save() {
        hasAttemptedCreate = true
        guard isValid else { return }

        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.startTranscriptionJob(
                    name: jobName.trimmingCharacters(in: .whitespaces),
                    mediaUri: mediaUri.trimmingCharacters(in: .whitespaces),
                    languageCode: languageCode,
                    mediaFormat: mediaFormat,
                    outputBucketName: outputBucketName.trimmingCharacters(in: .whitespaces).isEmpty
                        ? nil
                        : outputBucketName.trimmingCharacters(in: .whitespaces)
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
