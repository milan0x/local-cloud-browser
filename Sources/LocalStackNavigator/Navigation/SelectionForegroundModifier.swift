import SwiftUI

/// Applies `.foregroundStyle(.white)` when the row sits on a prominent background
/// (i.e., the List row is selected and focused), and `.primary` otherwise.
/// Uses the system's `backgroundProminence` environment value, which updates
/// in sync with the selection highlight — eliminating the timing gap that occurs
/// when binding foreground color to `selectedIDs.contains()` manually.
struct SelectionForegroundModifier: ViewModifier {
    @Environment(\.backgroundProminence) private var backgroundProminence

    func body(content: Content) -> some View {
        content
            .foregroundStyle(backgroundProminence == .increased ? Color.white : Color.primary)
    }
}

extension View {
    func selectionForeground() -> some View {
        modifier(SelectionForegroundModifier())
    }
}
