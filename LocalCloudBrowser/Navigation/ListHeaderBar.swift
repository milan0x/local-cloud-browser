import SwiftUI

struct ListHeaderBar<Trailing: View>: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager

    let title: String
    let subtitle: String?
    let autoRefresh: AutoRefreshManager
    let isReadOnly: Bool
    let onRefresh: () -> Void
    let onCreate: () -> Void
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        autoRefresh: AutoRefreshManager,
        isReadOnly: Bool,
        onRefresh: @escaping () -> Void,
        onCreate: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.autoRefresh = autoRefresh
        self.isReadOnly = isReadOnly
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
            ListHeaderButton("plus", action: {
                guard licenseManager.guardWriteAction(for: appState.selectedRoute) else { return }
                onCreate()
            })
            AutoRefreshMenuView(interval: Binding(get: { autoRefresh.interval }, set: { autoRefresh.interval = $0 })) {
                onRefresh()
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
        self.onRefresh = onRefresh
        self.onCreate = onCreate
        self.trailing = ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled, help: deleteHelp, action: onDelete)
    }
}
