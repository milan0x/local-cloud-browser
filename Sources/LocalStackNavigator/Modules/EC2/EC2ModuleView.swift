import SwiftUI

struct EC2ModuleView: View {
    @EnvironmentObject private var client: LocalStackClient
    @EnvironmentObject private var appState: AppState
    @StateObject private var service: EC2Service
    @StateObject private var toolbarState = EC2ToolbarState()

    @State private var entityType: EC2EntityType = .instances
    @State private var selectedInstanceId: String?
    @State private var selectedGroupId: String?
    @State private var selectedKeyName: String?

    // Session restore
    @State private var restoreEntityType: EC2EntityType?
    @State private var restoreEntityName: String?

    init() {
        _service = StateObject(wrappedValue: EC2Service())
        if let saved = LastSessionStore.load() {
            if let typeStr = saved.ec2EntityType, let type = EC2EntityType(rawValue: typeStr) {
                _restoreEntityType = State(initialValue: type)
            }
            _restoreEntityName = State(initialValue: saved.ec2EntityName)
        }
    }

    private var hasSelection: Bool {
        switch entityType {
        case .instances: selectedInstanceId != nil
        case .securityGroups: selectedGroupId != nil
        case .keyPairs: selectedKeyName != nil
        }
    }

    var body: some View {
        HSplitView {
            EC2EntityListView(
                service: service,
                toolbarState: toolbarState,
                entityType: $entityType,
                selectedInstanceId: $selectedInstanceId,
                selectedGroupId: $selectedGroupId,
                selectedKeyName: $selectedKeyName,
                restoreEntityType: restoreEntityType,
                restoreEntityName: restoreEntityName
            )
            .frame(width: 280)

            Group {
                if let instanceId = selectedInstanceId, entityType == .instances {
                    EC2InstanceDetailView(service: service, instanceId: instanceId)
                } else if let groupId = selectedGroupId, entityType == .securityGroups {
                    EC2SecurityGroupDetailView(service: service, groupId: groupId)
                } else if let keyName = selectedKeyName, entityType == .keyPairs {
                    EC2KeyPairDetailView(keyName: keyName)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Select a resource")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            EC2Toolbar(
                state: toolbarState,
                isReadOnly: appState.isReadOnly,
                hasSelection: hasSelection
            )
        }
        .onChange(of: entityType) {
            saveSession()
        }
        .onChange(of: selectedInstanceId) {
            saveSession()
        }
        .onChange(of: selectedGroupId) {
            saveSession()
        }
        .onChange(of: selectedKeyName) {
            saveSession()
        }
        .onAppear {
            service.updateClient(client)
        }
    }

    private func saveSession() {
        let name: String?
        switch entityType {
        case .instances: name = selectedInstanceId
        case .securityGroups: name = selectedGroupId
        case .keyPairs: name = selectedKeyName
        }
        LastSessionStore.saveEC2Entity(type: entityType.rawValue, name: name)
    }
}

// MARK: - Key Pair Detail (simple enough to inline)

struct EC2KeyPairDetailView: View {
    let keyName: String
    @EnvironmentObject private var appState: AppState

    // We show key pair info from the list data, loaded by parent
    // For key pairs, the list already has all the data we need

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(keyName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text("Key Pair")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Key Pair Info") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Key Name") {
                                CopyableValue(text: keyName)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }
                .padding()
            }
        }
    }
}

struct EC2Module: LocalStackModule {
    let serviceName = "EC2"
    let serviceIcon = "server.rack"
    let serviceEndpoint = "/ec2"

    func makeMainView() -> AnyView {
        AnyView(EC2ModuleView())
    }
}
