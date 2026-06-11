import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var transferManager: TransferManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let tm = transferManager, tm.hasActiveTransfers else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Uploads in Progress"
        alert.informativeText = "There are active file transfers. Quitting will cancel them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Transfers & Quit")
        alert.addButton(withTitle: "Don't Quit")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main
struct LocalCloudBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var client: CloudClient
    @StateObject private var profileStore: ConnectionProfileStore
    @StateObject private var transferManager = TransferManager()

    init() {
        Log.info("Local Cloud Browser starting", category: "App")
        AppPreferences.cleanPreviewTempDirectory()

        UserDefaults.standard.register(defaults: [
            AppPreferences.restoreLastSessionKey: true,
            AppPreferences.autoRefreshIntervalKey: 5,
        ])

        let state = AppState()
        let store = ConnectionProfileStore()
        state.onSettingsDetected = { [weak store] profileId, detected in
            guard let store else { return }
            guard var profile = store.profiles.first(where: { $0.id == profileId }) else { return }
            var changed = false
            if let value = detected.endpointType, profile.endpointType != value {
                profile.endpointType = value
                changed = true
            }
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
        }
        if LastSessionStore.isEnabled, let saved = LastSessionStore.load() {
            state.selectedRoute = saved.route
        } else {
            LastSessionStore.clearSubResources()
        }
        Self.purgeLegacyLicenseDefaults()

        _appState = StateObject(wrappedValue: state)
        _client = StateObject(wrappedValue: CloudClient(appState: state))
        _profileStore = StateObject(wrappedValue: store)
    }

    /// One-time cleanup of UserDefaults keys left behind by the old paid
    /// licensing system. Removes per-service create counters and the
    /// cached StoreKit purchase flag so they don't linger forever on
    /// existing installs.
    private static func purgeLegacyLicenseDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("freeCreates_") {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: "storeKit.cachedIsPurchased")
        defaults.removeObject(forKey: "trialStartDate")
    }

    var body: some Scene {
        WindowGroup("Local Cloud Browser") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(client)
                .environmentObject(profileStore)
                .environmentObject(appState.autoRefresh)
                .environmentObject(transferManager)
                .frame(minWidth: 880, minHeight: 500)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    appDelegate.transferManager = transferManager
                    if !appState.isLocalEndpoint {
                        Task { await client.fetchCallerIdentity() }
                    }
                }
                .onChange(of: appState.connectionVersion) {
                    if !appState.isLocalEndpoint {
                        Task { await client.fetchCallerIdentity() }
                    }
                    // Credentials or endpoint just changed — any in-flight
                    // uploads are signed with stale credentials pointing at
                    // the wrong endpoint. Cancel them before they fail with
                    // 403 or hit the new endpoint with the old auth.
                    if transferManager.hasActiveTransfers {
                        transferManager.cancelAll()
                    }
                }
                // Silent refresh whenever the app becomes active — covers cold
                // launches, reopens from the Dock, and regaining focus after
                // another app was frontmost. Every list view subscribes via
                // `.onAutoRefresh`, so only the visible service actually fetches
                // (no 27-service thundering herd). The ListLoader 2-second
                // debounce collapses duplicates with `.task` on first launch.
                .onChange(of: scenePhase) { _, newPhase in
                    // Skip when the user has suspended auto-refresh (live AWS)
                    // to avoid surprise billable API calls on every window focus.
                    if newPhase == .active && !appState.autoRefresh.isSuspended {
                        appState.autoRefresh.triggerNow()
                    }
                }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            FileCommands()
            ConnectionCommands()
            DonationCommands()
            S3PasteboardCommands()
            HelpCommands()
        }

        WindowGroup(id: "s3-browser", for: S3BrowserTarget.self) { $target in
            if let target {
                S3BrowserWindow(target: target)
                    .environmentObject(appState)
                    .environmentObject(client)
                    .environmentObject(appState.autoRefresh)
                    .environmentObject(transferManager)
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
    @FocusedValue(\.s3RefreshAction) private var s3Refresh

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                s3Refresh?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(s3Refresh == nil)
        }

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
