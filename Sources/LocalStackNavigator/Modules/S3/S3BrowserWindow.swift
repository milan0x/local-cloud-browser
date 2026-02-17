import SwiftUI

/// Target describing which bucket and optional prefix to open in a new window.
struct S3BrowserTarget: Codable, Hashable {
    let bucket: String
    let prefix: String?
}

/// A lightweight S3 browser window — just the object browser, no sidebar or bucket list.
struct S3BrowserWindow: View {
    let target: S3BrowserTarget
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: S3Service
    @StateObject private var toolbarState = S3ToolbarState()

    init(target: S3BrowserTarget) {
        self.target = target
        _service = StateObject(wrappedValue: S3Service())
    }

    var body: some View {
        S3ObjectBrowserView(
            service: service,
            bucket: S3Bucket(name: target.bucket, creationDate: nil),
            paneID: "window-\(target.bucket)",
            toolbarState: toolbarState
        )
        .toolbar {
            S3Toolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasBucket: true
            )
        }
        .navigationTitle(windowTitle)
        .onAppear {
            service.updateClient(client)
        }
    }

    private var windowTitle: String {
        if let prefix = target.prefix, !prefix.isEmpty {
            return "\(target.bucket) — \(prefix)"
        }
        return target.bucket
    }
}
