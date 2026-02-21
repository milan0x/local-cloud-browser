import SwiftUI

struct S3ConfigHintView: View {
    @EnvironmentObject private var appState: AppState
    let errorMessage: String
    let onRetry: () -> Void

    @State private var autoRetryCount = 0
    private static let maxAutoRetries = 3

    var body: some View {
        if isS3ConfigError {
            VStack(spacing: 8) {
                Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("S3 domain not configured")
                    .fontWeight(.medium)
                Text("This endpoint may require an S3 domain to route requests correctly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if autoRetryCount < Self.maxAutoRetries {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Detecting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 12) {
                        Button("Edit Connection") {
                            appState.editActiveProfileRequest = .init(showAdvanced: true)
                        }
                        Button("Retry") { onRetry() }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: autoRetryCount) {
                guard autoRetryCount < Self.maxAutoRetries else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                autoRetryCount += 1
                onRetry()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { onRetry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isS3ConfigError: Bool {
        appState.s3Domain.trimmingCharacters(in: .whitespaces).isEmpty
            && errorMessage.contains("Failed to parse S3 XML response")
    }
}
