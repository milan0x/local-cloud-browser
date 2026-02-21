import SwiftUI

struct ListLoadingContent<Content: View, ErrorContent: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    let errorMessage: String?
    let loadingMessage: String
    var emptyIcon: String? = nil
    var emptyMessage: String? = nil
    var emptySecondaryMessage: String? = nil
    let onRetry: () -> Void
    @ViewBuilder let errorContent: (String) -> ErrorContent
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading && isEmpty {
            VStack(spacing: 12) {
                ProgressView(loadingMessage)
                ConnectionRetryingLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, isEmpty {
            errorContent(errorMessage)
        } else if isEmpty, let emptyIcon, let emptyMessage {
            EmptyStateView(icon: emptyIcon, message: emptyMessage, secondaryMessage: emptySecondaryMessage)
        } else {
            content()
        }
    }
}

extension ListLoadingContent where ErrorContent == _DefaultErrorContent {
    init(
        isLoading: Bool,
        isEmpty: Bool,
        errorMessage: String?,
        loadingMessage: String,
        emptyIcon: String? = nil,
        emptyMessage: String? = nil,
        emptySecondaryMessage: String? = nil,
        onRetry: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.errorMessage = errorMessage
        self.loadingMessage = loadingMessage
        self.emptyIcon = emptyIcon
        self.emptyMessage = emptyMessage
        self.emptySecondaryMessage = emptySecondaryMessage
        self.onRetry = onRetry
        self.errorContent = { msg in _DefaultErrorContent(message: msg, onRetry: onRetry) }
        self.content = content
    }
}

struct _DefaultErrorContent: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") { onRetry() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
