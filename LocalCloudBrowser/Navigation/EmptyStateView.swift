import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let message: String
    var secondaryMessage: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            if let secondaryMessage {
                Text(secondaryMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
