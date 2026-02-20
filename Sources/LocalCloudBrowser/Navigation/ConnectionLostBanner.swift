import SwiftUI

struct ConnectionLostBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption)
            Text("Connection lost — showing cached data")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
    }
}

struct ConnectionRetryingLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.connectionError != nil {
            Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
