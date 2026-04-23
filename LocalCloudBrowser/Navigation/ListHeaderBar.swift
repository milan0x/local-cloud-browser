import SwiftUI

struct ListHeaderBar<Trailing: View>: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager

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
                onRefresh()
            }
            Spacer()
            if isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Read-only mode is active. Disable it in the toolbar to make changes.")
            }
            if !licenseManager.isPaid, !isReadOnly, let route = appState.selectedRoute {
                let remaining = licenseManager.remainingCreates(for: route)
                Text("\(remaining)/\(LicenseManager.freeCreateLimit)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
                    .help(remaining > 0
                          ? "\(remaining) free creates remaining"
                          : "Click to sync with actual resource count")
                    .onTapGesture {
                        if licenseManager.syncCreateCount(for: route, actualCount: itemCount) {
                            Log.info("Synced free slots for \(route.displayName): actual=\(itemCount)", category: "License")
                        }
                    }
            }
            ListHeaderButton("plus", isDisabled: isReadOnly, help: isReadOnly ? "Read-only mode is active" : "", action: {
                guard licenseManager.guardWriteAction(for: appState.selectedRoute) else { return }
                onCreate()
            })
            if !appState.isLocalEndpoint {
                ProductionAutoRefreshBadge()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            } else {
                AutoRefreshMenuView(interval: Binding(get: { autoRefresh.interval }, set: { autoRefresh.interval = $0 })) {
                    onRefresh()
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
