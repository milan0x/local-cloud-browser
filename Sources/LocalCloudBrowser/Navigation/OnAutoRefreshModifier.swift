import SwiftUI
import Combine

struct OnAutoRefreshModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    let canRefresh: () -> Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(appState.autoRefresh.triggerPublisher) {
                guard canRefresh() else { return }
                action()
            }
    }
}

extension View {
    func onAutoRefresh(canRefresh: @escaping () -> Bool, action: @escaping () -> Void) -> some View {
        modifier(OnAutoRefreshModifier(canRefresh: canRefresh, action: action))
    }
}
