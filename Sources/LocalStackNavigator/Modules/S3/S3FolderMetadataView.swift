import SwiftUI
import AppKit

struct S3FolderMetadataView: View {
    @ObservedObject var service: S3Service
    @Environment(\.dismiss) private var dismiss
    let bucket: String
    let prefix: String

    @State private var objectCount: Int?
    @State private var totalSize: Int64?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedField: String?

    private var displayName: String {
        let trimmed = String(prefix.dropLast())
        return trimmed.components(separatedBy: "/").last ?? prefix
    }

    private var s3URI: String {
        "s3://\(bucket)/\(prefix)"
    }

    private var parentPath: String {
        let parts = prefix.dropLast().components(separatedBy: "/").dropLast()
        return parts.isEmpty ? "/" : parts.joined(separator: "/") + "/"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                    Text("in \(bucket)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Scanning folder contents...")
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
            } else {
                VStack(spacing: 14) {
                    // Stats
                    HStack(spacing: 24) {
                        statBlock(
                            label: "Objects",
                            value: "\(objectCount ?? 0)",
                            icon: "doc.on.doc"
                        )
                        Divider()
                            .frame(height: 36)
                        statBlock(
                            label: "Total Size",
                            value: ByteCountFormatter.string(fromByteCount: totalSize ?? 0, countStyle: .file),
                            icon: "internaldrive"
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    Divider()
                        .padding(.horizontal)

                    // Detail rows
                    VStack(spacing: 8) {
                        detailRow(label: "Path", value: prefix)
                        detailRow(label: "Parent", value: parentPath)
                        detailRow(label: "S3 URI", value: s3URI, copiable: true)
                    }
                    .padding(.horizontal)

                    Spacer()
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
        .frame(width: 380, height: 320)
        .task {
            do {
                let allObjects = try await service.listAllObjects(bucket: bucket, prefix: prefix)
                let contents = allObjects.filter { $0.key != prefix }
                objectCount = contents.count
                totalSize = contents.reduce(0) { $0 + $1.size }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func statBlock(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.medium)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailRow(label: String, value: String, copiable: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
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
                    .font(.caption)
                    .frame(width: 14, height: 14)
                    .animation(.easeInOut(duration: 0.15), value: copiedField)
                }
                .buttonStyle(.borderless)
                .help("Copy \(label)")
            }
        }
    }
}
