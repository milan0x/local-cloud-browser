import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let route = appState.selectedRoute {
                detailView(for: route)
            } else {
                welcomeView
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                regionBadge
            }
        }
    }

    private var isGlobalService: Bool {
        appState.selectedRoute == .s3
    }

    private var regionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.caption)
            Text(isGlobalService ? "Global" : appState.region)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .opacity(isGlobalService ? 0.5 : 1.0)
        .help(isGlobalService ? "S3 buckets are global on LocalStack, not region-specific" : "Region: \(appState.region)")
    }

    @ViewBuilder
    private func detailView(for route: Route) -> some View {
        switch route {
        case .s3:
            S3ModuleView()
        case .sqs:
            SQSModuleView()
        case .sns:
            SNSModuleView()
        case .secretsManager:
            SecretsManagerModuleView()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("LocalStack Navigator")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Select a service from the sidebar to get started.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
