import SwiftUI

struct TransferPopoverView: View {
    @EnvironmentObject private var transferManager: TransferManager

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var visibleItems: [TransferItem] {
        let active = transferManager.items.filter { !$0.state.isFinished }
        let finished = transferManager.items.filter { $0.state.isFinished }.prefix(10)
        return active + finished
    }

    private var hiddenCount: Int {
        max(0, transferManager.items.count - visibleItems.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            if transferManager.items.isEmpty {
                emptyState
            } else {
                transferList
            }
            footer
        }
        .frame(width: 340, height: min(max(CGFloat(visibleItems.count) * 56 + 48, 140), 360))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No transfers")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transferList: some View {
        List {
            ForEach(visibleItems) { item in
                TransferRowView(item: item, transferManager: transferManager)
            }
            if hiddenCount > 0 {
                Text("and \(hiddenCount) more queued")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if transferManager.hasActiveTransfers {
                Button("Cancel All") {
                    transferManager.cancelAll()
                }
                .controlSize(.small)
            }
            Spacer()
            if transferManager.items.contains(where: { $0.state.isFinished }) {
                Button("Clear") {
                    transferManager.clearCompleted()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Transfer Row

struct TransferRowView: View {
    @ObservedObject var item: TransferItem
    let transferManager: TransferManager

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            directionIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                stateView
            }

            Spacer(minLength: 0)

            trailingView
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var directionIcon: some View {
        if item.direction == .upload {
            Image(systemName: "arrow.up")
                .font(.caption)
                .foregroundStyle(.blue)
        } else {
            Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch item.state {
        case .queued:
            Text("Waiting...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .active:
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: item.fractionCompleted)
                    .progressViewStyle(.linear)
                Text("\(Self.byteFormatter.string(fromByteCount: item.bytesTransferred)) / \(Self.byteFormatter.string(fromByteCount: item.totalBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .completed:
            Text("Completed")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Failed: \(message)")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        case .cancelled:
            Text("Cancelled")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        if item.state == .active || item.state == .queued {
            Button {
                // Route through the manager so all invariants (objectWillChange,
                // task nil-out, pending-queue filter if queued) are honored —
                // previously this bypassed the manager by flipping state +
                // task.cancel() inline, which missed the cleanup paths.
                transferManager.cancel(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        } else if item.state == .completed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else if case .failed = item.state {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
