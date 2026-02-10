import SwiftUI

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
            .frame(width: 220)

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
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear {
            service.updateClient(client)
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
