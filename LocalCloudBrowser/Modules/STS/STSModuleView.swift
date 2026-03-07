import SwiftUI

struct STSModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service = STSService()

    @State private var identity: CallerIdentity?
    @State private var isLoadingIdentity = false
    @State private var identityError: String?

    // Assume Role form
    @State private var roleArn = ""
    @State private var sessionName = "navigator-session"
    @State private var durationSeconds = "3600"
    @State private var isAssuming = false
    @State private var assumedCredentials: AssumedRoleCredentials?
    @State private var serviceError: ServiceError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                callerIdentitySection
                assumeRoleSection
                if let creds = assumedCredentials {
                    STSAssumeRoleResultView(credentials: creds) {
                        assumedCredentials = nil
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { loadIdentity() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .toolbarHitTarget()
                }
                .help("Refresh Caller Identity")
            }
        }
        .task { loadIdentity() }
        .onChange(of: appState.connectionVersion) {
            identity = nil
            assumedCredentials = nil
            loadIdentity()
        }
        .onAppear {
            service.updateClient(client)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Caller Identity Section

    private var callerIdentitySection: some View {
        GroupBox("Caller Identity") {
            if isLoadingIdentity && identity == nil {
                ProgressView("Loading identity...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let error = identityError, identity == nil {
                VStack(spacing: 8) {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadIdentity() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if let id = identity {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow("Account") {
                        CopyableValue(text: id.account, monospaced: true)
                    }
                    labeledRow("ARN") {
                        CopyableValue(text: id.arn, monospaced: true)
                    }
                    labeledRow("User ID") {
                        CopyableValue(text: id.userId, monospaced: true)
                    }
                }
                .padding(4)
            } else {
                Text("No identity loaded")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Assume Role Section

    private var assumeRoleSection: some View {
        GroupBox("Assume Role") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Role ARN")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("arn:aws:iam::000000000000:role/MyRole", text: $roleArn)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("session-name", text: $sessionName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration (seconds)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("3600", text: $durationSeconds)
                }

                HStack {
                    Spacer()
                    Button("Assume Role") {
                        assumeRole()
                    }
                    .disabled(!isAssumeRoleValid || isAssuming || appState.isReadOnly)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            content()
        }
    }

    private var isAssumeRoleValid: Bool {
        let arn = roleArn.trimmingCharacters(in: .whitespaces)
        let name = sessionName.trimmingCharacters(in: .whitespaces)
        guard !arn.isEmpty, !name.isEmpty else { return false }
        guard let dur = Int(durationSeconds.trimmingCharacters(in: .whitespaces)),
              dur >= 900, dur <= 43200 else { return false }
        return true
    }

    // MARK: - Data

    private func loadIdentity() {
        isLoadingIdentity = true
        identityError = nil
        Task {
            do {
                identity = try await service.getCallerIdentity()
            } catch {
                identityError = error.localizedDescription
            }
            isLoadingIdentity = false
        }
    }

    private func assumeRole() {
        isAssuming = true
        assumedCredentials = nil
        Task {
            do {
                let dur = Int(durationSeconds.trimmingCharacters(in: .whitespaces)) ?? 3600
                assumedCredentials = try await service.assumeRole(
                    roleArn: roleArn.trimmingCharacters(in: .whitespaces),
                    sessionName: sessionName.trimmingCharacters(in: .whitespaces),
                    durationSeconds: dur
                )
            } catch {
                serviceError = error.asServiceError
            }
            isAssuming = false
        }
    }
}

struct STSModule: ServiceModule {
    let serviceName = "STS"
    let serviceIcon = "person.badge.key"
    let serviceEndpoint = "/sts"

    func makeMainView() -> AnyView {
        AnyView(STSModuleView())
    }
}
