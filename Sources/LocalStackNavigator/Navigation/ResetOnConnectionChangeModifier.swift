import SwiftUI

struct ResetOnConnectionChangeModifier: ViewModifier {
    @EnvironmentObject var appState: AppState
    let includeRegion: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.connectionVersion) { action() }
            .onChange(of: appState.region) {
                if includeRegion { action() }
            }
    }
}

extension View {
    func resetOnConnectionChange(includeRegion: Bool = true, _ action: @escaping () -> Void) -> some View {
        modifier(ResetOnConnectionChangeModifier(includeRegion: includeRegion, action: action))
    }
}
