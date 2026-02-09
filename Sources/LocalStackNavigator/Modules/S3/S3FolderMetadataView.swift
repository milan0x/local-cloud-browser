import SwiftUI

struct S3FolderMetadataView: View {
    @ObservedObject var service: S3Service
    @Environment(\.dismiss) private var dismiss
    let bucket: String
    let prefix: String

    @State private var objectCount: Int?
    @State private var totalSize: Int64?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var displayName: String {
        let trimmed = String(prefix.dropLast())
        return trimmed.components(separatedBy: "/").last ?? prefix
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
                    Text(prefix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                VStack(spacing: 16) {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(width: 340, height: 220)
        .task {
            do {
                let objects = try await service.listAllObjects(bucket: bucket, prefix: prefix)
                objectCount = objects.count
                totalSize = objects.reduce(0) { $0 + $1.size }
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
}
