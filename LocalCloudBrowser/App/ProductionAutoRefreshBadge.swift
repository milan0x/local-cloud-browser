import SwiftUI

struct ProductionAutoRefreshBadge: View {
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 10))
                Text("Auto-refresh off")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Auto-refresh is disabled for production connections")
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(.orange)
                    Text("Auto-refresh is disabled")
                        .font(.headline)
                }
                Text("This connection targets a real AWS endpoint. Auto-refresh is disabled to prevent repeated API calls that could incur charges on your account.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Use the refresh button to update the current view manually.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 300)
        }
    }
}
