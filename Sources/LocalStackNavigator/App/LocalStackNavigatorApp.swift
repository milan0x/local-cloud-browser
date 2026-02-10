import SwiftUI
import AppKit

@main
struct LocalStackNavigatorApp: App {
    @StateObject private var appState: AppState
    @StateObject private var client: LocalStackClient
    @StateObject private var profileStore: ConnectionProfileStore

    init() {
        // Make the process a regular foreground app (dock icon, menu bar, keyboard focus).
        // Required because SPM executable targets don't get this automatically.
        NSApplication.shared.setActivationPolicy(.regular)

        Log.info("LocalStack Navigator starting", category: "App")

        let state = AppState()
        let store = ConnectionProfileStore()
        if let active = store.activeProfile {
            state.applyProfile(active)
        }
        _appState = StateObject(wrappedValue: state)
        _client = StateObject(wrappedValue: LocalStackClient(appState: state))
        _profileStore = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
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
                .environmentObject(appState.autoRefresh)
        }
    }
}
