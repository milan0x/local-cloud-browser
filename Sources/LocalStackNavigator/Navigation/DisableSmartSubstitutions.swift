import AppKit
import SwiftUI

/// Disables macOS smart quotes, smart dashes, and automatic text replacement
/// on both TextEditor (own NSTextView) and all TextFields in the same window
/// (shared field editor).
///
/// Usage: `TextEditor(text: $body).disableSmartSubstitutions()`
extension View {
    func disableSmartSubstitutions(textContainerInset: NSSize? = nil) -> some View {
        background(SmartSubstitutionsFixer(textContainerInset: textContainerInset))
    }
}

private struct SmartSubstitutionsFixer: NSViewRepresentable {
    let textContainerInset: NSSize?

    func makeNSView(context: Context) -> NSView {
        let view = FixerView()
        view.textContainerInset = textContainerInset
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class FixerView: NSView {
    var textContainerInset: NSSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBeginEditing),
            name: NSText.didBeginEditingNotification,
            object: nil
        )
    }

    override func removeFromSuperview() {
        removeObserver()
        super.removeFromSuperview()
    }

    private func removeObserver() {
        NotificationCenter.default.removeObserver(self, name: NSText.didBeginEditingNotification, object: nil)
    }

    @objc private func handleDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              textView.window === window else { return }
        Self.disableSubstitutions(on: textView)
    }

    private func configureExistingTextViews() {
        // Walk up to find the enclosing NSTextView for TextEditor
        var ancestor: NSView? = superview
        for _ in 0..<10 {
            guard let view = ancestor else { return }
            if let textView = Self.findTextView(in: view) {
                Self.disableSubstitutions(on: textView)
                if let inset = textContainerInset {
                    textView.textContainerInset = inset
                }
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
