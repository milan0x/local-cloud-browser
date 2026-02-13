import AppKit
import SwiftUI

/// Disables macOS smart quotes, smart dashes, and automatic text replacement
/// on both TextEditor (own NSTextView) and all TextFields in the same window
/// (shared field editor).
///
/// Usage: `TextEditor(text: $body).disableSmartSubstitutions()`
extension View {
    func disableSmartSubstitutions() -> some View {
        background(SmartSubstitutionsFixer())
    }
}

private struct SmartSubstitutionsFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        FixerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class FixerView: NSView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            removeObserver()
            return
        }

        // Configure any existing NSTextView immediately
        DispatchQueue.main.async { [weak self] in
            self?.configureExistingTextViews()
        }

        // Observe every editing session start — catches SwiftUI reconfiguration,
        // field editor reuse, and focus changes between TextFields.
        removeObserver()
        observer = NotificationCenter.default.addObserver(
            forName: NSText.didBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] notification in
            guard let textView = notification.object as? NSTextView,
                  textView.window === window else { return }
            Self.disableSubstitutions(on: textView)
        }
    }

    override func removeFromSuperview() {
        removeObserver()
        super.removeFromSuperview()
    }

    private func removeObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func configureExistingTextViews() {
        // Walk up to find the enclosing NSTextView for TextEditor
        var ancestor: NSView? = superview
        for _ in 0..<10 {
            guard let view = ancestor else { return }
            if let textView = Self.findTextView(in: view) {
                Self.disableSubstitutions(on: textView)
                return
            }
            ancestor = view.superview
        }
    }

    private static func disableSubstitutions(on textView: NSTextView) {
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }
}
