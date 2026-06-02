import SwiftUI

struct KinesisFirehoseCreateView: View {
    @ObservedObject var service: KinesisFirehoseService
    @Environment(\.dismiss) private var dismiss
    @State private var streamName = ""
    @State private var s3BucketARN = ""
    @State private var s3Prefix = ""
    @State private var compression = "UNCOMPRESSED"
    @State private var bufferingInterval = 300
    @State private var bufferingSize = 5
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let compressionFormats = ["UNCOMPRESSED", "GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY"]

    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Delivery Stream Name", text: $streamName)

                Section("S3 Destination") {
                    TextField("S3 Bucket ARN", text: $s3BucketARN)
                    TextField("Prefix (optional)", text: $s3Prefix)

                    Picker("Compression", selection: $compression) {
                        ForEach(compressionFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }

                    Stepper("Buffering Interval: \(bufferingInterval)s", value: $bufferingInterval, in: 60...900, step: 60)
                    Stepper("Buffering Size: \(bufferingSize) MB", value: $bufferingSize, in: 1...128)
                }
        }
    }

    private var isValid: Bool {
        !streamName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !s3BucketARN.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createDeliveryStream(
                    name: streamName.trimmingCharacters(in: .whitespaces),
                    s3BucketARN: s3BucketARN.trimmingCharacters(in: .whitespaces),
                    s3Prefix: s3Prefix.trimmingCharacters(in: .whitespaces),
                    bufferingInterval: bufferingInterval,
                    bufferingSize: bufferingSize,
                    compression: compression
                )
                onCreate?(streamName.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
