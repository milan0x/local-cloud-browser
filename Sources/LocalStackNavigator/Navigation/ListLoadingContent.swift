import SwiftUI

struct ListLoadingContent<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    let errorMessage: String?
    let loadingMessage: String
    let onRetry: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading && isEmpty {
            VStack(spacing: 12) {
                ProgressView(loadingMessage)
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { onRetry() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content()
        }
    }
}
