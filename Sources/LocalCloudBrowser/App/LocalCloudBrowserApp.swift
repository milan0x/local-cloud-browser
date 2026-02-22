import SwiftUI
import AppKit

@main
struct LocalCloudBrowserApp: App {
    @StateObject private var appState: AppState
    @StateObject private var client: CloudClient
    @StateObject private var profileStore: ConnectionProfileStore

    init() {
        // Make the process a regular foreground app (dock icon, menu bar, keyboard focus).
        // Required because SPM executable targets don't get this automatically.
        NSApplication.shared.setActivationPolicy(.regular)

        Log.info("Local Cloud Browser starting", category: "App")
        AppPreferences.cleanPreviewTempDirectory()

        UserDefaults.standard.register(defaults: [
            AppPreferences.restoreLastSessionKey: true,
        ])

        let state = AppState()
        let store = ConnectionProfileStore()
        state.onSettingsDetected = { [weak store] profileId, detected in
            guard let store else { return }
            guard var profile = store.profiles.first(where: { $0.id == profileId }) else { return }
            var changed = false
            if let value = detected.healthPath, profile.healthPath.trimmingCharacters(in: .whitespaces).isEmpty {
                profile.healthPath = value
                changed = true
            }
            if let value = detected.s3Domain, profile.s3Domain.trimmingCharacters(in: .whitespaces).isEmpty {
                profile.s3Domain = value
                changed = true
            }
            if let value = detected.apiGatewayDomain, profile.apiGatewayDomain.trimmingCharacters(in: .whitespaces).isEmpty {
                profile.apiGatewayDomain = value
                changed = true
            }
            if changed {
                store.update(profile)
                Log.info("Persisted auto-detected settings for \"\(profile.name)\"", category: "App")
            }
        }
        if let active = store.activeProfile {
            state.applyProfile(active)
        } else {
            state.startHealthCheck()
        }
        if LastSessionStore.isEnabled, let saved = LastSessionStore.load() {
            state.selectedRoute = saved.route
        } else {
            LastSessionStore.clearSubResources()
        }
        _appState = StateObject(wrappedValue: state)
        _client = StateObject(wrappedValue: CloudClient(appState: state))
        _profileStore = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup("Local Cloud Browser") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(client)
                .environmentObject(profileStore)
                .environmentObject(appState.autoRefresh)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            S3PasteboardCommands()
            HelpCommands()
        }

        WindowGroup(id: "s3-browser", for: S3BrowserTarget.self) { $target in
            if let target {
                S3BrowserWindow(target: target)
                    .environmentObject(appState)
                    .environmentObject(client)
                    .environmentObject(appState.autoRefresh)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.autoRefresh)
        }
    }
}

struct S3PasteboardCommands: Commands {
    @FocusedValue(\.s3CopyAction) private var s3Copy
    @FocusedValue(\.s3PasteAction) private var s3Paste
    @FocusedValue(\.s3DeleteAction) private var s3Delete

    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if isTextFieldFocused {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else if let s3Copy {
                    s3Copy()
                } else {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if isTextFieldFocused {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else if let s3Paste {
                    s3Paste()
                } else {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Delete") {
                if isTextFieldFocused {
                    NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
                } else if let s3Delete {
                    s3Delete()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
    }

    private var isTextFieldFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }
}
