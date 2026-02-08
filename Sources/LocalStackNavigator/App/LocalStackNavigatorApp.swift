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
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }
}
