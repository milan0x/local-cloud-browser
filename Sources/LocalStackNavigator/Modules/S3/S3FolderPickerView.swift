import SwiftUI

struct S3FolderPickerView: View {
    let service: S3Service
    let currentBucket: String
    let currentPrefix: String
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedBucket: String
    @State private var browsePrefix = ""
    @State private var folders: [S3Prefix] = []
    @State private var buckets: [S3Bucket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(service: S3Service, currentBucket: String, currentPrefix: String, onSelect: @escaping (String, String) -> Void) {
        self.service = service
        self.currentBucket = currentBucket
        self.currentPrefix = currentPrefix
        self.onSelect = onSelect
        _selectedBucket = State(initialValue: currentBucket)
    }

    private var pathComponents: [String] {
        guard !browsePrefix.isEmpty else { return [] }
        let trimmed = browsePrefix.hasSuffix("/") ? String(browsePrefix.dropLast()) : browsePrefix
        return trimmed.components(separatedBy: "/")
    }

    private var displayPath: String {
        if browsePrefix.isEmpty {
            return selectedBucket + " /"
        }
        return selectedBucket + " / " + browsePrefix
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Choose Destination")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Bucket picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Bucket")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedBucket) {
                    ForEach(buckets) { b in
                        Text(b.name).tag(b.name)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedBucket) {
                    browsePrefix = ""
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Breadcrumb
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button(selectedBucket) {
                        browsePrefix = ""
                    }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)

                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button(component) {
                            let prefix = pathComponents.prefix(index + 1).joined(separator: "/") + "/"
                            browsePrefix = prefix
                        }
                        .buttonStyle(.plain)
                        .fontWeight(index == pathComponents.count - 1 ? .medium : .regular)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            Divider()

            // Folder list
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folders.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text("No subfolders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(folders) { folder in
                            Button {
                                browsePrefix = folder.prefix
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    Text(folder.displayName)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(height: 200)

            Divider()

            // Current selection display
            HStack(spacing: 4) {
                Text("Destination:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayPath)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move Here") {
                    onSelect(selectedBucket, browsePrefix)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420)
        .task(id: selectedBucket + "|" + browsePrefix) {
            await loadFolders()
        }
        .task {
            await loadBuckets()
        }
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await service.listObjects(
                bucket: selectedBucket,
                prefix: browsePrefix
            )
            folders = result.commonPrefixes
        } catch {
            errorMessage = "Failed to load folders"
            folders = []
        }
        isLoading = false
    }

    private func loadBuckets() async {
        do {
            buckets = try await service.listBuckets()
            if !buckets.contains(where: { $0.name == selectedBucket }) {
                if let first = buckets.first {
                    selectedBucket = first.name
                }
            }
        } catch {
            buckets = [S3Bucket(name: currentBucket, creationDate: nil)]
        }
    }
}
