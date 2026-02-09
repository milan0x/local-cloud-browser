import SwiftUI

struct S3IconBrowserView: View {
    let items: [S3ObjectBrowserView.RowItem]
    let onNavigate: (String) -> Void
    let onDownload: (String) -> Void
    let onShowMetadata: (String) -> Void
    let onDelete: (String) -> Void
    let isReadOnly: Bool

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    iconCell(item)
                }
            }
            .padding(16)
        }
    }

    private func iconCell(_ item: S3ObjectBrowserView.RowItem) -> some View {
        VStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 36))
                .foregroundStyle(item.isFolder ? Color.accentColor : Color.secondary)
                .frame(height: 44)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) {
            if item.isFolder {
                onNavigate(item.fullKey)
            } else {
                onDownload(item.fullKey)
            }
        }
        .contextMenu {
            if item.isFolder {
                Button("Open") { onNavigate(item.fullKey) }
            } else {
                Button("Download") { onDownload(item.fullKey) }
                Button("Metadata") { onShowMetadata(item.fullKey) }
                Divider()
                Button("Delete", role: .destructive) { onDelete(item.fullKey) }
                    .disabled(isReadOnly)
            }
        }
    }
}
