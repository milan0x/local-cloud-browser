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

struct CredentialExpiredBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.credentialExpired {
            HStack(spacing: 6) {
                Image(systemName: "key.slash")
                    .font(.caption)
                Text("Session token may have expired for \"\(appState.activeConnectionName)\"")
                    .font(.caption)
                Spacer()
                Button("Update Credentials") {
                    appState.editActiveProfileRequest = AppState.EditProfileRequest(showAdvanced: false)
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
        }
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

struct RetryBannerView: View {
    let attempt: RetryAttempt
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Retrying (\(attempt.attemptNumber)/\(attempt.maxAttempts))...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let onCancel {
                Button("Cancel", role: .destructive) {
                    onCancel()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
