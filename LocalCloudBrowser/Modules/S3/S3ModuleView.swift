import SwiftUI

struct S3ModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: S3Service
    @StateObject private var toolbarState = S3ToolbarState()

    @State private var selectedBucketIDs: Set<S3Bucket.ID> = []
    @State private var activeBucket: S3Bucket?

    // Pane focus
    @State private var detailSearchFocusTrigger = 0
    @State private var listSearchFocusTrigger = 0
    @State private var listPaneFocusTrigger = 0
    @State private var detailPaneFocusTrigger = 0

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
                searchFocusTrigger: listSearchFocusTrigger,
                paneFocusTrigger: listPaneFocusTrigger
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                appState.sidebarFocusTrigger += 1
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                guard activeBucket != nil else { return .ignored }
                detailPaneFocusTrigger += 1
                return .handled
            }

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
                        searchFocusTrigger: detailSearchFocusTrigger,
                        paneFocusTrigger: detailPaneFocusTrigger
                    )
                } else {
                    EmptyDetailView(icon: "externaldrive", message: "Select a bucket")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
            .onKeyPress(.leftArrow) {
                guard !isTextFieldFirstResponder() else { return .ignored }
                listPaneFocusTrigger += 1
                return .handled
            }
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
        }
        .cmdFSearchCycling(
            hasDetail: activeBucket != nil,
            activeItemID: activeBucket?.id,
            listSearchFocusTrigger: $listSearchFocusTrigger,
            detailSearchFocusTrigger: $detailSearchFocusTrigger
        )
        .onChange(of: appState.moduleListFocusTrigger) {
            listPaneFocusTrigger += 1
        }
        .onAppear {
            service.updateClient(client)
        }
    }
}

struct S3Module: ServiceModule {
    let serviceName = "S3"
    let serviceIcon = "externaldrive"
    let serviceEndpoint = "/s3"

    func makeMainView() -> AnyView {
        AnyView(S3ModuleView())
    }
}
