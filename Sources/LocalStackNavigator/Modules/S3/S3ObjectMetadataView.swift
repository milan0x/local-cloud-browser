import SwiftUI

struct S3ObjectMetadataView: View {
    @ObservedObject var service: S3Service
    @Environment(\.dismiss) private var dismiss
    let bucket: String
    let objectKey: String

    @State private var detail: S3ObjectDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Object Metadata")
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
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                Form {
                    Section("General") {
                        LabeledContent("Key", value: detail.key)
                        LabeledContent("Size") {
                            let formatter = ByteCountFormatter()
                            Text(formatter.string(fromByteCount: detail.size))
                        }
                        LabeledContent("Content-Type", value: detail.contentType)
                        LabeledContent("Last Modified", value: detail.lastModified)
                        LabeledContent("ETag", value: detail.etag)
                    }

                    if !detail.metadata.isEmpty {
                        Section("Custom Metadata") {
                            ForEach(detail.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                LabeledContent(key, value: value)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 420, height: 360)
        .task {
            do {
                detail = try await service.headObject(bucket: bucket, key: objectKey)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
