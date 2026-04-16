import SwiftUI

struct IAMModuleView: View {
    @EnvironmentObject private var client: CloudClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: IAMService
    @StateObject private var toolbarState = IAMToolbarState()

    @State private var entityType: IAMEntityType = .users
    @State private var selectedUserName: String?
    @State private var selectedRoleName: String?
    @State private var selectedPolicyArn: String?

    // Session restore
    @State private var restoreEntityType: IAMEntityType?
    @State private var restoreEntityName: String?

    init() {
        _service = StateObject(wrappedValue: IAMService())
        if let saved = LastSessionStore.load() {
            if let typeStr = saved.iamEntityType, let type = IAMEntityType(rawValue: typeStr) {
                _restoreEntityType = State(initialValue: type)
            }
            _restoreEntityName = State(initialValue: saved.iamEntityName)
        }
    }

    private var hasSelection: Bool {
        switch entityType {
        case .users: selectedUserName != nil
        case .roles: selectedRoleName != nil
        case .policies: selectedPolicyArn != nil
        }
    }

    var body: some View {
        HSplitView {
            IAMEntityListView(
                service: service,
                toolbarState: toolbarState,
                entityType: $entityType,
                selectedUserName: $selectedUserName,
                selectedRoleName: $selectedRoleName,
                selectedPolicyArn: $selectedPolicyArn,
                restoreEntityType: restoreEntityType,
                restoreEntityName: restoreEntityName
            )
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 350)

            Group {
                if let userName = selectedUserName, entityType == .users {
                    IAMDetailBrowserView(
                        service: service,
                        entityType: .users,
                        entityName: userName
                    )
                } else if let roleName = selectedRoleName, entityType == .roles {
                    IAMDetailBrowserView(
                        service: service,
                        entityType: .roles,
                        entityName: roleName
                    )
                } else if let policyArn = selectedPolicyArn, entityType == .policies {
                    IAMDetailBrowserView(
                        service: service,
                        entityType: .policies,
                        entityName: policyArn
                    )
                } else {
                    EmptyDetailView(icon: "person.2", message: "Select an entity")
                }
            }
            .frame(minWidth: 140)
            .layoutPriority(1)
        }
        .toolbar {
            IAMToolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasSelection: hasSelection
            )
        }
        .onChange(of: entityType) {
            saveSession()
        }
        .onChange(of: selectedUserName) {
            saveSession()
        }
        .onChange(of: selectedRoleName) {
            saveSession()
        }
        .onChange(of: selectedPolicyArn) {
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func saveSession() {
        let name: String?
        switch entityType {
        case .users: name = selectedUserName
        case .roles: name = selectedRoleName
        case .policies: name = selectedPolicyArn
        }
        LastSessionStore.saveIAMEntity(type: entityType.rawValue, name: name)
    }
}

struct IAMModule: ServiceModule {
    let serviceName = "IAM"
    let serviceIcon = "person.2"
    let serviceEndpoint = "/iam"

    func makeMainView() -> AnyView {
        AnyView(IAMModuleView())
    }
}
