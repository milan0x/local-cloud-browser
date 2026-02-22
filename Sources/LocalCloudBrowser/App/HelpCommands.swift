import SwiftUI
import AppKit

// MARK: - Focused value key

struct ShowFeedbackKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showFeedback: Binding<Bool>? {
        get { self[ShowFeedbackKey.self] }
        set { self[ShowFeedbackKey.self] = newValue }
    }
}

// MARK: - App constants

enum AppInfo {
    static let version = "1.0.0"
    static let contactEmail = "mlnapps@icloud.com"
}

// MARK: - Help menu commands

struct HelpCommands: Commands {
    @FocusedValue(\.showFeedback) private var showFeedback

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Send Feedback...") {
                showFeedback?.wrappedValue = true
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])

            Divider()

            Button("About Local Cloud Browser") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationName: "Local Cloud Browser",
                    .applicationVersion: AppInfo.version,
                    .credits: Self.aboutCredits,
                ])
            }
        }
    }

    private static var aboutCredits: NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "You can contact me at:\n",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))

        result.append(NSAttributedString(
            string: AppInfo.contactEmail,
            attributes: [
                .font: font,
                .link: URL(string: "mailto:\(AppInfo.contactEmail)")!,
            ]
        ))

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))

        return result
    }
}
