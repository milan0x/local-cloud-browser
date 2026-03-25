import SwiftUI

/// A two-pane split view with a draggable divider and persisted width.
/// Replaces HSplitView which ignores SwiftUI's idealWidth.
struct ResizableSplitView<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing
    let minWidth: CGFloat
    let defaultWidth: CGFloat
    let maxWidth: CGFloat
    let storageKey: String

    @SceneStorage private var paneWidth: Double
    @State private var dragStartWidth: Double?

    init(
        storageKey: String,
        minWidth: CGFloat = 200,
        defaultWidth: CGFloat = 280,
        maxWidth: CGFloat = 450,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.storageKey = storageKey
        self.minWidth = minWidth
        self.defaultWidth = defaultWidth
        self.maxWidth = maxWidth
        self.leading = leading()
        self.trailing = trailing()
        _paneWidth = SceneStorage(wrappedValue: Double(defaultWidth), storageKey)
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: paneWidth)

            divider

            trailing
                .frame(minWidth: 400)
        }
    }

    private var divider: some View {
        ZStack {
            Color(nsColor: .separatorColor)
                .frame(width: 1)
            Color.clear
                .frame(width: 9)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = paneWidth }
                            let new = (dragStartWidth ?? paneWidth) + value.translation.width
                            paneWidth = max(Double(minWidth), min(new, Double(maxWidth)))
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
        }
        .frame(width: 9)
    }
}
