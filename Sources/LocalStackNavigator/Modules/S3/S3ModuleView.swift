import SwiftUI
import AppKit

struct S3ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @StateObject private var service: S3Service

    @State private var selectedBucketIDs: Set<S3Bucket.ID> = []
    @State private var activeBucket: S3Bucket?

    init() {
        // Placeholder — real client injected via onAppear
        _service = StateObject(wrappedValue: S3Service(client: LocalStackClient(appState: AppState())))
    }

    var body: some View {
        HSplitView {
            S3BucketListView(
                service: service,
                selectedBucketIDs: $selectedBucketIDs,
                activeBucket: $activeBucket
            )
            .frame(width: 260)

            // Primary pane
            Group {
                if let bucket = activeBucket {
                    S3ObjectBrowserView(
                        service: service,
                        bucket: bucket,
                        paneID: "main"
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a bucket")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack(spacing: 4) {
                                Button {} label: { Image(systemName: "chevron.left") }
                                    .disabled(true)
                                    .help("Back")
                                Button {} label: { Image(systemName: "chevron.right") }
                                    .disabled(true)
                                    .help("Forward")
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {} label: { Label("Policy", systemImage: "doc.text") }
                                .disabled(true)
                                .help("Bucket Policy")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {} label: { Label("Folder", systemImage: "folder.badge.plus") }
                                .disabled(true)
                                .help("Create Folder")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {} label: { Label("Upload", systemImage: "plus") }
                                .disabled(true)
                                .help("Upload File")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {} label: { Label("Delete", systemImage: "trash") }
                                .disabled(true)
                                .help("Delete Selected")
                        }
                    }
                }
            }
            .frame(minWidth: 400)
            .background(ToolbarDisplayModeSaver())
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

// MARK: - Toolbar Display Mode Persistence

private struct ToolbarDisplayModeSaver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ToolbarObserverView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ToolbarObserverView)?.restoreDisplayMode()
    }

    class ToolbarObserverView: NSView {
        private var observation: NSKeyValueObservation?
        private static let defaultsKey = "toolbarDisplayMode"

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation?.invalidate()
            observation = nil
            guard let toolbar = window?.toolbar else { return }

            restoreDisplayMode()

            let key = Self.defaultsKey
            observation = toolbar.observe(\.displayMode, options: [.new]) { _, change in
                if let mode = change.newValue {
                    UserDefaults.standard.set(Int(mode.rawValue), forKey: key)
                }
            }
        }

        func restoreDisplayMode() {
            guard let toolbar = window?.toolbar else { return }

            // Restore saved display mode
            if UserDefaults.standard.object(forKey: Self.defaultsKey) != nil {
                let saved = UserDefaults.standard.integer(forKey: Self.defaultsKey)
                let mode = NSToolbar.DisplayMode(rawValue: UInt(saved)) ?? .default
                if toolbar.displayMode != mode {
                    toolbar.displayMode = mode
                }
            }

        }

        deinit {
            observation?.invalidate()
        }
    }
}

struct S3Module: LocalStackModule {
    let serviceName = "S3"
    let serviceIcon = "externaldrive"
    let serviceEndpoint = "/s3"

    func makeMainView() -> AnyView {
        AnyView(S3ModuleView())
    }
}
