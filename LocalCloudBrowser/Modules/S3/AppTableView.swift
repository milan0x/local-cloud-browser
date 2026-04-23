import AppKit

/// NSTableView subclass used by the S3 object browser. Adds context-menu,
/// spacebar, plain-Delete-key, and empty-area-click handling on top of the
/// default behavior.
final class AppTableView: NSTableView {
    /// Builds an NSMenu for the given selected row indices on right-click.
    var contextMenuProvider: ((Set<Int>) -> NSMenu?)?

    /// Called when spacebar is pressed with the currently selected row indices.
    var spacebarHandler: ((Set<Int>) -> Void)?

    /// Called when the plain Delete / Backspace key is pressed with the
    /// currently selected row indices.
    var deleteHandler: ((Set<Int>) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        // If right-clicking a row that isn't in the current selection, select
        // just that row so the menu's actions apply to what was clicked.
        if clickedRow >= 0 && !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        // If right-clicking empty space, deselect to surface background actions.
        if clickedRow < 0 {
            deselectAll(nil)
        }

        return contextMenuProvider?(Set(selectedRowIndexes))
    }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        if chars == " " {
            spacebarHandler?(Set(selectedRowIndexes))
            return
        }
        // Plain Delete/Backspace (no modifiers) → forward to deleteHandler so
        // the owning SwiftUI view can trigger its destructive flow.
        if chars.unicodeScalars.first == "\u{7F}" || chars.unicodeScalars.first == "\u{8}" {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Let Cmd+Delete flow through the responder chain to SwiftUI command
            // handlers. Only intercept the plain Delete / Backspace keystroke.
            if modifiers.isEmpty {
                deleteHandler?(Set(selectedRowIndexes))
                return
            }
        }
        super.keyDown(with: event)
    }

    /// Deselect when the user clicks below the last row in empty space.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow < 0 {
            deselectAll(nil)
        }
        super.mouseDown(with: event)
    }
}
