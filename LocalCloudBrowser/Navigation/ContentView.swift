import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @EnvironmentObject private var licenseManager: LicenseManager
    @State private var showFeedback = false
    @State private var showWelcome = false
    @State private var showNewConnection = false

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
        .overlay(alignment: .bottomTrailing) {
            licenseBadge
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                regionBadge
            }
        }
        .focusedSceneValue(\.showFeedback, $showFeedback)
        .focusedSceneValue(\.showUpgrade, $licenseManager.showUpgradeSheet)
        .focusedSceneValue(\.profileStore, profileStore)
        .focusedSceneValue(\.appState, appState)
        .focusedSceneValue(\.showNewConnection) { showNewConnection = true }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $licenseManager.showUpgradeSheet) {
            UpgradeView()
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView()
        }
        .sheet(isPresented: $showNewConnection) {
            ConnectionProfileEditorView(
                existing: nil,
                canDelete: false,
                onSave: { profile in
                    profileStore.add(profile)
                }
            )
        }
        .onAppear {
            if !licenseManager.isPaid && !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
                UserDefaults.standard.set(true, forKey: "hasShownWelcome")
                showWelcome = true
            }
        }
        .onChange(of: appState.selectedRoute) {
            LastSessionStore.saveRoute(appState.selectedRoute)
        }
    }

    @ViewBuilder
    private var licenseBadge: some View {
        switch licenseManager.state {
        case .free:
            Button {
                licenseManager.showUpgradeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Unlock Unlimited")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .background(
                    Color(red: 0.15, green: 0.3, blue: 0.55),
                    in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Free plan — tap to upgrade")
        case .paid:
            EmptyView()
        }
    }

    private var isGlobalService: Bool {
        appState.selectedRoute == .s3 || appState.selectedRoute == .iam || appState.selectedRoute == .route53 || appState.selectedRoute == .sts
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
            .help("S3 buckets are global, not region-specific")
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
                        if region.code == appState.region {
                            Label("\(region.code) — \(region.displayName)", systemImage: "checkmark")
                        } else {
                            Text("\(region.code) — \(region.displayName)")
                        }
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
        case .ses:
            SESModuleView()
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
        case .cloudWatch:
            CloudWatchModuleView()
        case .eventBridge:
            EventBridgeModuleView()
        case .cloudFormation:
            CloudFormationModuleView()
        case .iam:
            IAMModuleView()
        case .apiGateway:
            APIGatewayModuleView()
        case .acm:
            ACMModuleView()
        case .kinesis:
            KinesisModuleView()
        case .kms:
            KMSModuleView()
        case .route53:
            Route53ModuleView()
        case .redshift:
            RedshiftModuleView()
        case .opensearch:
            OpenSearchModuleView()
        case .stepFunctions:
            StepFunctionsModuleView()
        case .ec2:
            EC2ModuleView()
        case .sts:
            STSModuleView()
        case .config:
            ConfigModuleView()
        case .resourceGroups:
            ResourceGroupsModuleView()
        case .transcribe:
            TranscribeModuleView()
        case .support:
            SupportModuleView()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Local Cloud Browser")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Select a service from the sidebar to get started.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
