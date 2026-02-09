import SwiftUI

struct S3ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @StateObject private var service: S3Service

    @State private var selectedBucket: S3Bucket?
    @State private var showSplitView = false
    @State private var splitBucket: S3Bucket?
    @State private var splitPrefix: String?

    init() {
        // Placeholder — real client injected via onAppear
        _service = StateObject(wrappedValue: S3Service(client: LocalStackClient(appState: AppState())))
    }

    var body: some View {
        HSplitView {
            S3BucketListView(
                service: service,
                selectedBucket: $selectedBucket,
                showSplitView: $showSplitView,
                onOpenInSplit: openInSplit
            )
            .frame(width: 220)

            // Primary pane
            Group {
                if let bucket = selectedBucket {
                    S3ObjectBrowserView(
                        service: service,
                        bucket: bucket,
                        paneID: "main",
                        onOpenInSplit: openInSplit
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
                }
            }
            .frame(minWidth: 400)

            // Split pane (conditional)
            if showSplitView, let bucket = splitBucket {
                Divider()
                S3ObjectBrowserView(
                    service: service,
                    bucket: bucket,
                    paneID: "split",
                    onOpenInSplit: nil
                )
                .frame(minWidth: 300)
            }
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func openInSplit(bucket: S3Bucket, prefix: String?) {
        splitBucket = bucket
        splitPrefix = prefix
        showSplitView = true
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
