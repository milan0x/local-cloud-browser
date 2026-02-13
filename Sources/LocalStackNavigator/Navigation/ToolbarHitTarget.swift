import SwiftUI

/// Expands a toolbar button's hit target to match the NSToolbar circle highlight.
///
/// SwiftUI toolbar buttons have a smaller click area than the AppKit-rendered
/// hover/press circle. Apply this modifier to the button's label so clicks
/// anywhere on the visible circle actually trigger the action.
struct ToolbarHitTarget: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }
}

extension View {
    func toolbarHitTarget() -> some View {
        modifier(ToolbarHitTarget())
    }
}
