import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore

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
        .onChange(of: appState.selectedRoute) {
            LastSessionStore.saveRoute(appState.selectedRoute)
        }
    }

    private var isGlobalService: Bool {
        appState.selectedRoute == .s3
    }

    @ViewBuilder
    private var regionBadge: some View {
        if isGlobalService {
            Menu { } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text("Global")
                }
            }
            .foregroundStyle(.secondary)
            .disabled(true)
            .help("S3 buckets are global on LocalStack, not region-specific")
        } else {
            Menu {
                ForEach(AWSRegion.allRegions, id: \.code) { region in
                    Button {
                        appState.region = region.code
                        if var profile = profileStore.activeProfile {
                            profile.region = region.code
                            profileStore.update(profile)
                        }
                    } label: {
                        Text("\(region.code) — \(region.displayName)")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(appState.region)
                }
            }
            .help("Region: \(appState.region) — Click to change")
        }
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
        case .dynamodb:
            DynamoDBModuleView()
        case .ssm:
            SSMModuleView()
        case .lambda:
            LambdaModuleView()
        case .cloudwatchLogs:
            CloudWatchLogsModuleView()
        case .eventBridge:
            EventBridgeModuleView()
        case .cloudFormation:
            CloudFormationModuleView()
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
