import SwiftUI

struct AutoRefreshIndicatorView: View {
    @ObservedObject var manager: AutoRefreshManager
    var onRefreshNow: (() -> Void)?

    var body: some View {
        if manager.isActive {
            Button {
                onRefreshNow?()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise")
                    Text("\(manager.countdownRemaining)s")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Click to refresh now")
        }
    }
}
