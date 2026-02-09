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
    @State private var hoveredFolder: String?

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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bucketPicker
            breadcrumb
            Divider()
            folderList
            Divider()
            destinationBar
            Divider()
            buttons
        }
        .frame(width: 440)
        .task(id: selectedBucket + "|" + browsePrefix) {
            await loadFolders()
        }
        .task {
            await loadBuckets()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose Destination")
                    .font(.headline)
                Text("Select a bucket and folder to move into")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Bucket Picker

    private var bucketPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
                .frame(width: 16)
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
        .padding(.vertical, 8)
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 0) {
            if !pathComponents.isEmpty {
                Button {
                    let parent = Array(pathComponents.dropLast())
                    browsePrefix = parent.isEmpty ? "" : parent.joined(separator: "/") + "/"
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    breadcrumbSegment(label: "/", isCurrent: pathComponents.isEmpty) {
                        browsePrefix = ""
                    }

                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.quaternary)
                        breadcrumbSegment(
                            label: component,
                            isCurrent: index == pathComponents.count - 1
                        ) {
                            browsePrefix = pathComponents.prefix(index + 1).joined(separator: "/") + "/"
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func breadcrumbSegment(label: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isCurrent ? Color.accentColor.opacity(0.1) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folder List

    private var folderList: some View {
        Group {
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if folders.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No subfolders")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("You can still move items here")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(height: 220)
    }

    private func folderRow(_ folder: S3Prefix) -> some View {
        let isHovered = hoveredFolder == folder.id
        return Button {
            browsePrefix = folder.prefix
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                Text(folder.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredFolder = hovering ? folder.id : nil
        }
    }

    // MARK: - Destination Bar

    private var destinationBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 13))
            Text(selectedBucket)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            if !browsePrefix.isEmpty {
                Text("/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.quaternary)
                Text(browsePrefix)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("/")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                onSelect(selectedBucket, browsePrefix)
                dismiss()
            } label: {
                Label("Move Here", systemImage: "arrow.right")
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Loading

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
