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
            HStack {
                Text("Folder Info")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Scanning folder contents...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section("General") {
                        LabeledContent("Name", value: displayName)
                        LabeledContent("Path", value: prefix)
                    }
                    Section("Contents") {
                        LabeledContent("Objects", value: "\(objectCount ?? 0)")
                        LabeledContent("Total Size") {
                            Text(ByteCountFormatter.string(fromByteCount: totalSize ?? 0, countStyle: .file))
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 380, height: 280)
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
}
