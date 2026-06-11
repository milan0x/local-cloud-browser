import SwiftUI

struct ListHeaderBar<Trailing: View>: View {
    @EnvironmentObject private var appState: AppState

    let title: String
    let subtitle: String?
    let autoRefresh: AutoRefreshManager
    let isReadOnly: Bool
    let itemCount: Int
    let onRefresh: () -> Void
    let onCreate: () -> Void
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        autoRefresh: AutoRefreshManager,
        isReadOnly: Bool,
        itemCount: Int = 0,
        onRefresh: @escaping () -> Void,
        onCreate: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.autoRefresh = autoRefresh
        self.isReadOnly = isReadOnly
        self.itemCount = itemCount
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.trailing = trailing()
    }

    /// Local reload plus a global trigger — the global trigger fans out to
    /// every view subscribed via `.onAutoRefresh`, so hitting refresh on a
    /// detail pane (e.g. S3 objects, SQS messages) also reloads the sidebar
    /// list (e.g. bucket list, queue list) instead of leaving it stale.
    private func performRefresh() {
        onRefresh()
        autoRefresh.triggerNow()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            AutoRefreshIndicatorView(manager: autoRefresh) {
                performRefresh()
            }
            Spacer()
            if isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Read-only mode is active. Disable it in the toolbar to make changes.")
            } else if !appState.isLocalEndpoint {
                // Writes against a remote endpoint are the dangerous state —
                // give it the ambient warning read-only used to have.
                Label("Writes enabled", systemImage: "lock.open")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .help("Write mode is active on a remote endpoint. Click the lock in the toolbar to re-enable read-only mode.")
            }
            ListHeaderButton("plus", isDisabled: isReadOnly, help: isReadOnly ? "Read-only mode is active" : "", action: onCreate)
            if !appState.isLocalEndpoint {
                ProductionAutoRefreshBadge()
                Button {
                    performRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            } else {
                AutoRefreshMenuView(interval: Binding(get: { autoRefresh.interval }, set: { autoRefresh.interval = $0 })) {
                    performRefresh()
                }
            }
            trailing
        }
        .frame(minHeight: 32) // match SearchBarView height in detail headers
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

extension ListHeaderBar where Trailing == ListHeaderButton {
    init(
        title: String,
        subtitle: String? = nil,
        autoRefresh: AutoRefreshManager,
        isReadOnly: Bool,
        itemCount: Int = 0,
        deleteDisabled: Bool,
        deleteHelp: String = "",
        onRefresh: @escaping () -> Void,
        onCreate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.autoRefresh = autoRefresh
        self.isReadOnly = isReadOnly
        self.itemCount = itemCount
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.trailing = ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled, help: deleteHelp, action: onDelete)
    }
}
