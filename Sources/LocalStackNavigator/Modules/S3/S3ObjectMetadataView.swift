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
    @State private var copiedField: String?

    private var s3URI: String { "s3://\(bucket)/\(objectKey)" }

    private var displayName: String {
        objectKey.components(separatedBy: "/").last ?? objectKey
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: iconForKey(objectKey))
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("in \(bucket)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let detail {
                ScrollView {
                    VStack(spacing: 0) {
                        sectionHeader("General")
                        VStack(spacing: 8) {
                            detailRow(label: "Key", value: detail.key)
                            detailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: detail.size, countStyle: .file))
                            detailRow(label: "Type", value: detail.contentType)
                            detailRow(label: "Modified", value: detail.lastModified)
                            detailRow(
                                label: "ETag",
                                value: detail.etag.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                                copiable: true
                            )
                            detailRow(label: "S3 URI", value: s3URI, copiable: true)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)

                        if !detail.metadata.isEmpty {
                            Divider()
                                .padding(.horizontal)
                            sectionHeader("Custom Metadata")
                            VStack(spacing: 8) {
                                ForEach(detail.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    detailRow(label: key, value: value)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 420, height: 380)
        .task {
            do {
                detail = try await service.headObject(bucket: bucket, key: objectKey)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func detailRow(label: String, value: String, copiable: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if copiable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copiedField = label
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedField == label { copiedField = nil }
                    }
                } label: {
                    ZStack {
                        Image(systemName: "doc.on.doc")
                            .opacity(copiedField == label ? 0 : 1)
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                            .opacity(copiedField == label ? 1 : 0)
                    }
                    .font(.callout)
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.15), value: copiedField)
                }
                .buttonStyle(.borderless)
                .help("Copy \(label)")
            }
        }
    }

    private func iconForKey(_ key: String) -> String {
        let ext = (key as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "svg", "webp", "ico", "bmp", "tiff":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "json", "xml", "yaml", "yml", "toml":
            return "doc.text"
        case "zip", "tar", "gz", "bz2", "rar", "7z":
            return "doc.zipper"
        case "mp4", "mov", "avi", "mkv", "webm":
            return "film"
        case "mp3", "wav", "aac", "flac", "ogg":
            return "waveform"
        default:
            return "doc"
        }
    }
}
