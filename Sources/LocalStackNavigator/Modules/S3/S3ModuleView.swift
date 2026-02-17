import SwiftUI

struct S3ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: S3Service
    @StateObject private var toolbarState = S3ToolbarState()

    @State private var selectedBucketIDs: Set<S3Bucket.ID> = []
    @State private var activeBucket: S3Bucket?

    // Cmd+F search focus cycling
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var lastSearchTarget = SearchTarget.detail

    // Session restore: captured once when the view is created (route switch or launch).
    // Passed to children so they can restore without reading stale data from LastSessionStore.
    @State private var restoreBucketName: String?
    @State private var restorePath: [String]?

    init() {
        // Placeholder — real client injected via onAppear
        _service = StateObject(wrappedValue: S3Service())
        if let saved = LastSessionStore.load() {
            _restoreBucketName = State(initialValue: saved.s3BucketName)
            _restorePath = State(initialValue: saved.s3Path)
        }
    }

    var body: some View {
        HSplitView {
            S3BucketListView(
                service: service,
                selectedBucketIDs: $selectedBucketIDs,
                activeBucket: $activeBucket,
                toolbarState: toolbarState,
                restoreBucketName: restoreBucketName,
                searchFocusTrigger: listSearchFocusTrigger
            )
            .frame(width: 280)

            // Primary pane
            Group {
                if let bucket = activeBucket {
                    S3ObjectBrowserView(
                        service: service,
                        bucket: bucket,
                        paneID: "main",
                        toolbarState: toolbarState,
                        restoreBucketName: restoreBucketName,
                        restorePath: restorePath,
                        searchFocusTrigger: detailSearchFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "externaldrive", message: "Select a bucket")
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            S3Toolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasBucket: activeBucket != nil
            )
        }
        .onChange(of: activeBucket) {
            toolbarState.reset()
            LastSessionStore.saveS3Bucket(activeBucket?.name)
            lastSearchTarget = .detail
        }
        .background {
            Button("") { cycleCmdF() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func cycleCmdF() {
        if activeBucket != nil, lastSearchTarget != .detail {
            detailSearchFocusTrigger += 1
            lastSearchTarget = .detail
        } else if activeBucket != nil {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        } else {
            listSearchFocusTrigger += 1
            lastSearchTarget = .list
        }
    }
}

private enum SearchTarget {
    case detail, list
}

struct S3Module: LocalStackModule {
    let serviceName = "S3"
    let serviceIcon = "externaldrive"
    let serviceEndpoint = "/s3"

    func makeMainView() -> AnyView {
        AnyView(S3ModuleView())
    }
}
