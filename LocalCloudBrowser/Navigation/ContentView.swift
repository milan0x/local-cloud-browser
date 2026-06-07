import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @State private var showFeedback = false
    @State private var showWelcome = false
    @State private var showNewConnection = false
    @State private var showPermissionBuilder = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            if let route = appState.selectedRoute {
                VStack(spacing: 0) {
                    detailView(for: route)
                }
            } else {
                welcomeView
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .bottomTrailing) {
            SupportHeartButton()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                TransferToolbarButton()
            }
            // Global Refresh — broadcasts via appState.autoRefresh, every
            // visible service list view picks it up through its
            // `.onAutoRefresh` subscription. Single source of truth so we
            // don't need to wire a Refresh action through 25 separate
            // service toolbars.
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.autoRefresh.triggerNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .toolbarHitTarget()
                }
                .help("Refresh")
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showPermissionBuilder = true
                } label: {
                    Image(systemName: "key.horizontal")
                        .toolbarHitTarget()
                }
                .help("Manage permissions — build an IAM policy for your AWS user.")
            }
            ToolbarItem(placement: .automatic) {
                readOnlyToggle
            }
        }
        .sheet(isPresented: $showPermissionBuilder) {
            PermissionBuilderSheet()
                .environmentObject(appState)
                .environmentObject(client)
        }
        .focusedSceneValue(\.showFeedback, $showFeedback)
        .focusedSceneValue(\.profileStore, profileStore)
        .focusedSceneValue(\.appState, appState)
        .focusedSceneValue(\.showNewConnection) { showNewConnection = true }
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
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
                    profileStore.setActive(id: profile.id)
                    appState.applyProfile(profile)
                }
            )
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasShownWelcome") {
                UserDefaults.standard.set(true, forKey: "hasShownWelcome")
                showWelcome = true
            }
        }
        .onChange(of: appState.selectedRoute) {
            LastSessionStore.saveRoute(appState.selectedRoute)
        }
    }

    @State private var isHoveringLock = false

    @ViewBuilder
    private var readOnlyToggle: some View {
        Button {
            appState.isReadOnly.toggle()
        } label: {
            Image(systemName: appState.isReadOnly ? "lock.fill" : "lock.open")
                .foregroundStyle(appState.isReadOnly ? .orange : .secondary)
                .toolbarHitTarget()
        }
        .help(appState.isReadOnly ? "Read-only mode (click to enable writes)" : "Write mode (click to enable read-only)")
        .accessibilityLabel(appState.isReadOnly ? "Read-only mode" : "Write mode")
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
            Text("Local Cloud Browser GUI")
                .font(.largeTitle)
                .fontWeight(.semibold)
            if profileStore.profiles.isEmpty {
                Text("Add a connection to get started.")
                    .foregroundStyle(.secondary)
                Button {
                    showNewConnection = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Connection")
                    }
                }
                .controlSize(.large)
            } else {
                Text("Select a service from the sidebar to get started.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
