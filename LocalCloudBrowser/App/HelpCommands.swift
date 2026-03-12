import SwiftUI
import AppKit

// MARK: - Focused value key

struct ShowFeedbackKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct ShowUpgradeKey: FocusedValueKey {
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

extension FocusedValues {
    var showFeedback: Binding<Bool>? {
        get { self[ShowFeedbackKey.self] }
        set { self[ShowFeedbackKey.self] = newValue }
    }

    var showUpgrade: Binding<Bool>? {
        get { self[ShowUpgradeKey.self] }
        set { self[ShowUpgradeKey.self] = newValue }
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
    @FocusedValue(\.showUpgrade) private var showUpgrade

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Unlock Unlimited...") {
                showUpgrade?.wrappedValue = true
            }

            Button("Restore Purchase...") {
                showUpgrade?.wrappedValue = true
            }

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
