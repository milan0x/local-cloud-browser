import SwiftUI
import AppKit

struct S3ObjectMetadataView: View {
    @ObservedObject var service: S3Service
    @Environment(\.dismiss) private var dismiss
    let bucket: String
    let objectKey: String

    @State private var detail: S3ObjectDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCopied = false
    @State private var showS3URICopied = false

    private var s3URI: String { "s3://\(bucket)/\(objectKey)" }

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
                        LabeledContent("ETag") {
                            HStack(spacing: 4) {
                                Text(detail.etag)
                                    .fixedSize()
                                Button {
                                    let clean = detail.etag.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(clean, forType: .string)
                                    showCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showCopied = false
                                    }
                                } label: {
                                    ZStack {
                                        Image(systemName: "doc.on.doc")
                                            .opacity(showCopied ? 0 : 1)
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.green)
                                            .opacity(showCopied ? 1 : 0)
                                    }
                                    .font(.caption)
                                    .frame(width: 14, height: 14)
                                    .animation(.easeInOut(duration: 0.15), value: showCopied)
                                }
                                .buttonStyle(.borderless)
                                .help("Copy ETag")
                            }
                        }
                        LabeledContent("S3 URI") {
                            HStack(spacing: 4) {
                                Text(s3URI)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(s3URI, forType: .string)
                                    showS3URICopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showS3URICopied = false
                                    }
                                } label: {
                                    ZStack {
                                        Image(systemName: "doc.on.doc")
                                            .opacity(showS3URICopied ? 0 : 1)
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.green)
                                            .opacity(showS3URICopied ? 1 : 0)
                                    }
                                    .font(.caption)
                                    .frame(width: 14, height: 14)
                                    .animation(.easeInOut(duration: 0.15), value: showS3URICopied)
                                }
                                .buttonStyle(.borderless)
                                .help("Copy S3 URI")
                            }
                        }
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
