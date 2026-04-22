import SwiftUI

struct EmptyDetailView: View {
    @EnvironmentObject private var appState: AppState

    let icon: String
    let message: String

    var body: some View {
        if let prompt = activePrompt {
            PermissionHelperView(prompt: prompt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(message)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private var activePrompt: PermissionDeniedPrompt? {
        guard let route = appState.selectedRoute,
              let key = route.serviceKey else { return nil }
        return appState.permissionDeniedPrompts[key]
    }
}
