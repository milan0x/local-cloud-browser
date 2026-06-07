import SwiftUI
import AppKit

// MARK: - Focused value key

struct ShowFeedbackKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct ProfileStoreKey: FocusedValueKey {
    typealias Value = ConnectionProfileStore
}

struct AppStateKey: FocusedValueKey {
    typealias Value = AppState
}

struct ShowNewConnectionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowDonationKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showFeedback: Binding<Bool>? {
        get { self[ShowFeedbackKey.self] }
        set { self[ShowFeedbackKey.self] = newValue }
    }

    var profileStore: ConnectionProfileStore? {
        get { self[ProfileStoreKey.self] }
        set { self[ProfileStoreKey.self] = newValue }
    }

    var appState: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }

    var showNewConnection: (() -> Void)? {
        get { self[ShowNewConnectionKey.self] }
        set { self[ShowNewConnectionKey.self] = newValue }
    }

    var showDonation: Binding<Bool>? {
        get { self[ShowDonationKey.self] }
        set { self[ShowDonationKey.self] = newValue }
    }
}

// MARK: - App constants

enum AppInfo {
    static let version = "1.0.0"
    static let contactEmail = "mlnapps@icloud.com"
    static let privacyPolicyURL = URL(string: "https://milan0x00.github.io/LocalCloudBrowser/privacy")!
}

// MARK: - Help menu commands

struct HelpCommands: Commands {
    @FocusedValue(\.showFeedback) private var showFeedback

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                showKeyboardShortcuts()
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("Privacy Policy...") {
                NSWorkspace.shared.open(AppInfo.privacyPolicyURL)
            }

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

        if let mailURL = URL(string: "mailto:\(AppInfo.contactEmail)") {
            result.append(NSAttributedString(
                string: AppInfo.contactEmail,
                attributes: [
                    .font: font,
                    .link: mailURL,
                ]
            ))
        }

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))

        return result
    }
}

// MARK: - Keyboard Shortcuts

private func showKeyboardShortcuts() {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
        styleMask: [.titled, .closable, .utilityWindow],
        backing: .buffered,
        defer: false
    )
    panel.title = "Keyboard Shortcuts"
    panel.isFloatingPanel = true
    panel.contentView = NSHostingView(rootView: KeyboardShortcutsView { panel.close() })
    panel.center()
    panel.makeKeyAndOrderFront(nil)
}

private struct KeyboardShortcutsView: View {
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shortcutSection("Navigation", items: [
                    ("Back", "⌘["),
                    ("Forward", "⌘]"),
                    ("Switch Panes", "← →"),
                    ("Enter Folder", "→ (folder selected)"),
                    ("Parent Folder", "← (in folder)"),
                ])
                shortcutSection("Files", items: [
                    ("Quick Look", "Space"),
                    ("Copy Selected", "⌘C"),
                    ("Paste / Upload", "⌘V"),
                    ("Delete Selected", "⌘⌫"),
                    ("Select All", "⌘A"),
                    ("Refresh", "⌘R"),
                ])
                shortcutSection("General", items: [
                    ("Search", "⌘F"),
                    ("New Connection", "⌘⇧N"),
                    ("Settings", "⌘,"),
                    ("Keyboard Shortcuts", "⌘/"),
                ])
            }
            .padding(20)
        }
        .frame(width: 360, height: 400)
    }

    private func shortcutSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(item.1)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - File menu commands

struct FileCommands: Commands {
    @FocusedValue(\.showNewConnection) private var showNewConnection

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection...") {
                showNewConnection?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Donation menu commands

struct DonationCommands: Commands {
    @FocusedValue(\.showDonation) private var showDonation

    var body: some Commands {
        CommandMenu("Donation") {
            Button("Support Development...") {
                showDonation?.wrappedValue = true
            }
            .disabled(showDonation == nil)
        }
    }
}

// MARK: - Connection menu commands

struct ConnectionCommands: Commands {
    @FocusedValue(\.profileStore) private var profileStore
    @FocusedValue(\.appState) private var appState

    var body: some Commands {
        CommandMenu("Connection") {
            if let profileStore, let appState {
                ForEach(profileStore.profiles) { profile in
                    Button {
                        profileStore.setActive(id: profile.id)
                        appState.applyProfile(profile)
                    } label: {
                        if profile.id == profileStore.activeProfileId {
                            Text("\u{2713} \(profile.name)")
                        } else {
                            Text("    \(profile.name)")
                        }
                    }
                }
            }
        }
    }
}
