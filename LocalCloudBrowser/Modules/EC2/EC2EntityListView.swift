import SwiftUI
import AppKit

struct EC2EntityListView: View {
    @ObservedObject var service: EC2Service
    @ObservedObject var toolbarState: EC2ToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var entityType: EC2EntityType
    @Binding var selectedInstanceId: String?
    @Binding var selectedGroupId: String?
    @Binding var selectedKeyName: String?
    var restoreEntityType: EC2EntityType?
    var restoreEntityName: String?

    @State private var instances: [EC2Instance] = []
    @State private var securityGroups: [EC2SecurityGroup] = []
    @State private var keyPairs: [EC2KeyPair] = []
    @State private var hasRestoredSession = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var serviceError: ServiceError?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""

    // Create sheets
    @State private var showRunInstanceSheet = false
    @State private var showCreateSecurityGroupSheet = false
    @State private var showCreateKeyPairSheet = false
    @State private var pendingSelectName: String?

    // Delete
    @State private var instancesToTerminate: [EC2Instance] = []
    @State private var groupsToDelete: [EC2SecurityGroup] = []
    @State private var keyPairsToDelete: [EC2KeyPair] = []

    // Selection tracking
    @State private var selectedInstanceIDs: Set<EC2Instance.ID> = []
    @State private var selectedGroupIDs: Set<EC2SecurityGroup.ID> = []
    @State private var selectedKeyPairIDs: Set<EC2KeyPair.ID> = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            // Mock CRUD banner
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("EC2 resources are simulated by LocalStack — no real VMs or infrastructure are created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.06))

            Divider()

            SegmentedTabPicker(selection: $entityType)

            Divider()
            listContent
        }
        // Create sheets
        .sheet(isPresented: $showRunInstanceSheet) {
            EC2RunInstanceView(
                service: service,
                keyPairs: keyPairs,
                securityGroups: securityGroups
            )
            .onDisappear { loadEntities(force: true) }
        }
        .sheet(isPresented: $showCreateSecurityGroupSheet) {
            EC2CreateSecurityGroupView(
                service: service,
                existingNames: Set(securityGroups.map(\.groupName))
            ) { name in
                pendingSelectName = name
            }
            .onDisappear { loadEntities(force: true) }
        }
        .sheet(isPresented: $showCreateKeyPairSheet) {
            EC2CreateKeyPairView(
                service: service,
                existingNames: Set(keyPairs.map(\.keyName))
            ) { name in
                pendingSelectName = name
            }
            .onDisappear { loadEntities(force: true) }
        }
        // Terminate instances alert
        .alert(
            instancesToTerminate.count == 1 ? "Terminate Instance" : "Terminate \(instancesToTerminate.count) Instances",
            isPresented: Binding(get: { !instancesToTerminate.isEmpty }, set: { if !$0 { instancesToTerminate = [] } })
        ) {
            Button("Terminate", role: .destructive) { terminateInstances(instancesToTerminate) }
            Button("Cancel", role: .cancel) { instancesToTerminate = [] }
        } message: {
            if instancesToTerminate.count == 1, let inst = instancesToTerminate.first {
                Text("Are you sure you want to terminate instance \"\(inst.displayName)\"?")
            } else {
                Text("Are you sure you want to terminate \(instancesToTerminate.count) instances?")
            }
        }
        // Delete security groups alert
        .alert(
            groupsToDelete.count == 1 ? "Delete Security Group" : "Delete \(groupsToDelete.count) Security Groups",
            isPresented: Binding(get: { !groupsToDelete.isEmpty }, set: { if !$0 { groupsToDelete = [] } })
        ) {
            Button("Delete", role: .destructive) { deleteSecurityGroups(groupsToDelete) }
            Button("Cancel", role: .cancel) { groupsToDelete = [] }
        } message: {
            if groupsToDelete.count == 1, let sg = groupsToDelete.first {
                Text("Are you sure you want to delete security group \"\(sg.groupName)\"?")
            } else {
                Text("Are you sure you want to delete \(groupsToDelete.count) security groups?")
            }
        }
        // Delete key pairs alert
        .alert(
            keyPairsToDelete.count == 1 ? "Delete Key Pair" : "Delete \(keyPairsToDelete.count) Key Pairs",
            isPresented: Binding(get: { !keyPairsToDelete.isEmpty }, set: { if !$0 { keyPairsToDelete = [] } })
        ) {
            Button("Delete", role: .destructive) { deleteKeyPairs(keyPairsToDelete) }
            Button("Cancel", role: .cancel) { keyPairsToDelete = [] }
        } message: {
            if keyPairsToDelete.count == 1, let kp = keyPairsToDelete.first {
                Text("Are you sure you want to delete key pair \"\(kp.keyName)\"?")
            } else {
                Text("Are you sure you want to delete \(keyPairsToDelete.count) key pairs?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadEntities() }
        .onAutoRefresh(canRefresh: { !showRunInstanceSheet && !showCreateSecurityGroupSheet && !showCreateKeyPairSheet && !isLoading }) {
            loadEntities(force: true, silent: true)
        }
        .resetOnConnectionChange {
            clearAllSelections()
            loadEntities(force: true)
        }
        .onChange(of: entityType) {
            searchText = ""
        }
        .onChange(of: selectedInstanceIDs) {
            if selectedInstanceIDs.count == 1, let id = selectedInstanceIDs.first {
                selectedInstanceId = id
            } else {
                selectedInstanceId = nil
            }
        }
        .onChange(of: selectedGroupIDs) {
            if selectedGroupIDs.count == 1, let id = selectedGroupIDs.first {
                selectedGroupId = id
            } else {
                selectedGroupId = nil
            }
        }
        .onChange(of: selectedKeyPairIDs) {
            if selectedKeyPairIDs.count == 1, let id = selectedKeyPairIDs.first {
                selectedKeyName = id
            } else {
                selectedKeyName = nil
            }
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            toolbarState.pendingAction = nil
            switch action {
            case .createEntity:
                showCreateSheet()
            case .deleteSelected:
                deleteCurrentSelection()
            }
        }
    }

    private func clearAllSelections() {
        selectedInstanceIDs = []
        selectedGroupIDs = []
        selectedKeyPairIDs = []
        selectedInstanceId = nil
        selectedGroupId = nil
        selectedKeyName = nil
        instances = []
        securityGroups = []
        keyPairs = []
    }

    // MARK: - Header

    private var listHeader: some View {
        ListHeaderBar(
            title: "EC2",
            autoRefresh: appState.autoRefresh,
            isReadOnly: appState.isReadOnly,
            itemCount: currentItemCount,
            deleteDisabled: deleteDisabled,
            deleteHelp: "Delete",
            onRefresh: { loadEntities(force: true) },
            onCreate: { showCreateSheet() },
            onDelete: { deleteCurrentSelection() }
        )
    }

    private var currentItemCount: Int {
        switch entityType {
        case .instances: return instances.count
        case .securityGroups: return securityGroups.count
        case .keyPairs: return keyPairs.count
        }
    }

    private var deleteDisabled: Bool {
        if appState.isReadOnly { return true }
        switch entityType {
        case .instances: return selectedInstanceIDs.isEmpty
        case .securityGroups: return selectedGroupIDs.isEmpty
        case .keyPairs: return selectedKeyPairIDs.isEmpty
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        switch entityType {
        case .instances: instancesListContent
        case .securityGroups: securityGroupsListContent
        case .keyPairs: keyPairsListContent
        }
    }

    // MARK: - Instances List

    private var filteredInstances: [EC2Instance] {
        guard !searchText.isEmpty else { return instances }
        let query = searchText.lowercased()
        return instances.filter {
            $0.instanceId.lowercased().contains(query) ||
            ($0.nameTag?.lowercased().contains(query) ?? false) ||
            $0.instanceType.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var instancesListContent: some View {
        if isLoading && instances.isEmpty {
            ProgressView("Loading instances...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, instances.isEmpty {
            errorView(errorMessage)
        } else if instances.isEmpty {
            emptyView("No instances", icon: "server.rack")
        } else {
            VStack(spacing: 0) {
                if instances.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter instances")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredInstances, selection: $selectedInstanceIDs) { instance in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(instance.state.color)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(instance.displayName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(instance.instanceId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(instance.instanceType)
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                    .selectionForeground()
                    .tag(instance.id)
                    .contextMenu { instanceContextMenu(instance) }
                }
                .contextMenu { createContextMenu }
                ListStatusBar(totalCount: instances.count, selectedCount: selectedInstanceIDs.count, noun: "instance")
            }
        }
    }

    @ViewBuilder
    private func instanceContextMenu(_ instance: EC2Instance) -> some View {
        Button("Copy Instance ID") { copyToClipboard(instance.instanceId) }
        if let ip = instance.privateIpAddress {
            Button("Copy Private IP") { copyToClipboard(ip) }
        }
        if let ip = instance.publicIpAddress {
            Button("Copy Public IP") { copyToClipboard(ip) }
        }
        Button("Copy as AWS CLI") {
            copyToClipboard(instance.describeInstanceCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Launch Instance") { showRunInstanceSheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if instance.state.canStart {
            Button("Start") { startInstance(instance) }
                .disabled(appState.isReadOnly)
        }
        if instance.state.canStop {
            Button("Stop") { stopInstance(instance) }
                .disabled(appState.isReadOnly)
        }
        if instance.state.canReboot {
            Button("Reboot") { rebootInstance(instance) }
                .disabled(appState.isReadOnly)
        }
        if instance.state.canTerminate {
            Button("Terminate", role: .destructive) { instancesToTerminate = [instance] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Security Groups List

    private var filteredSecurityGroups: [EC2SecurityGroup] {
        guard !searchText.isEmpty else { return securityGroups }
        let query = searchText.lowercased()
        return securityGroups.filter {
            $0.groupName.lowercased().contains(query) ||
            $0.groupId.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var securityGroupsListContent: some View {
        if isLoading && securityGroups.isEmpty {
            ProgressView("Loading security groups...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, securityGroups.isEmpty {
            errorView(errorMessage)
        } else if securityGroups.isEmpty {
            emptyView("No security groups", icon: "shield")
        } else {
            VStack(spacing: 0) {
                if securityGroups.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter security groups")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredSecurityGroups, selection: $selectedGroupIDs) { sg in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sg.groupName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(sg.groupId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !sg.inboundRules.isEmpty || !sg.outboundRules.isEmpty {
                                Text("\(sg.inboundRules.count)in/\(sg.outboundRules.count)out")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .selectionForeground()
                    .tag(sg.id)
                    .contextMenu { securityGroupContextMenu(sg) }
                }
                .contextMenu { createContextMenu }
                ListStatusBar(totalCount: securityGroups.count, selectedCount: selectedGroupIDs.count, noun: "security group")
            }
        }
    }

    @ViewBuilder
    private func securityGroupContextMenu(_ sg: EC2SecurityGroup) -> some View {
        Button("Copy Group ID") { copyToClipboard(sg.groupId) }
        Button("Copy Group Name") { copyToClipboard(sg.groupName) }
        Button("Copy as AWS CLI") {
            copyToClipboard(sg.describeGroupCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Create Security Group") { showCreateSecurityGroupSheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if selectedGroupIDs.count > 1 && selectedGroupIDs.contains(sg.id) {
            let selected = securityGroups.filter { selectedGroupIDs.contains($0.id) }
            Button("Delete \(selected.count) Security Groups", role: .destructive) { groupsToDelete = selected }
                .disabled(appState.isReadOnly)
        } else {
            Button("Delete", role: .destructive) { groupsToDelete = [sg] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Key Pairs List

    private var filteredKeyPairs: [EC2KeyPair] {
        guard !searchText.isEmpty else { return keyPairs }
        let query = searchText.lowercased()
        return keyPairs.filter { $0.keyName.lowercased().contains(query) }
    }

    @ViewBuilder
    private var keyPairsListContent: some View {
        if isLoading && keyPairs.isEmpty {
            ProgressView("Loading key pairs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, keyPairs.isEmpty {
            errorView(errorMessage)
        } else if keyPairs.isEmpty {
            emptyView("No key pairs", icon: "key")
        } else {
            VStack(spacing: 0) {
                if keyPairs.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter key pairs")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredKeyPairs, selection: $selectedKeyPairIDs) { kp in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kp.keyName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(kp.keyPairId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .selectionForeground()
                    .tag(kp.id)
                    .contextMenu { keyPairContextMenu(kp) }
                }
                .contextMenu { createContextMenu }
                ListStatusBar(totalCount: keyPairs.count, selectedCount: selectedKeyPairIDs.count, noun: "key pair")
            }
        }
    }

    @ViewBuilder
    private func keyPairContextMenu(_ kp: EC2KeyPair) -> some View {
        Button("Copy Key Name") { copyToClipboard(kp.keyName) }
        Button("Copy Key Pair ID") { copyToClipboard(kp.keyPairId) }
        Button("Copy Fingerprint") { copyToClipboard(kp.keyFingerprint) }
        Button("Copy as AWS CLI") {
            copyToClipboard(kp.describeKeyPairCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Create Key Pair") { showCreateKeyPairSheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if selectedKeyPairIDs.count > 1 && selectedKeyPairIDs.contains(kp.id) {
            let selected = keyPairs.filter { selectedKeyPairIDs.contains($0.id) }
            Button("Delete \(selected.count) Key Pairs", role: .destructive) { keyPairsToDelete = selected }
                .disabled(appState.isReadOnly)
        } else {
            Button("Delete", role: .destructive) { keyPairsToDelete = [kp] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Shared Views

    @ViewBuilder
    private var createContextMenu: some View {
        switch entityType {
        case .instances:
            Button("Launch Instance") { showRunInstanceSheet = true }
                .disabled(appState.isReadOnly)
        case .securityGroups:
            Button("Create Security Group") { showCreateSecurityGroupSheet = true }
                .disabled(appState.isReadOnly)
        case .keyPairs:
            Button("Create Key Pair") { showCreateKeyPairSheet = true }
                .disabled(appState.isReadOnly)
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") { loadEntities(force: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyView(_ text: String, icon: String) -> some View {
        EmptyStateView(icon: icon, message: text)
            .contextMenu { createContextMenu }
    }

    // MARK: - Actions

    private func showCreateSheet() {
        switch entityType {
        case .instances: showRunInstanceSheet = true
        case .securityGroups: showCreateSecurityGroupSheet = true
        case .keyPairs: showCreateKeyPairSheet = true
        }
    }

    private func deleteCurrentSelection() {
        switch entityType {
        case .instances:
            let selected = instances.filter { selectedInstanceIDs.contains($0.id) && $0.state.canTerminate }
            if !selected.isEmpty { instancesToTerminate = selected }
        case .securityGroups:
            let selected = securityGroups.filter { selectedGroupIDs.contains($0.id) }
            if !selected.isEmpty { groupsToDelete = selected }
        case .keyPairs:
            let selected = keyPairs.filter { selectedKeyPairIDs.contains($0.id) }
            if !selected.isEmpty { keyPairsToDelete = selected }
        }
    }

    // MARK: - Data

    private func loadEntities(force: Bool = false, silent: Bool = false) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                async let loadedInstances = service.listInstances()
                async let loadedGroups = service.listSecurityGroups()
                async let loadedKeys = service.listKeyPairs()

                let (i, sg, kp) = try await (loadedInstances, loadedGroups, loadedKeys)
                let freshInstances = i.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                let freshGroups = sg.sorted { $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending }
                let freshKeys = kp.sorted { $0.keyName.localizedStandardCompare($1.keyName) == .orderedAscending }

                if instances != freshInstances { instances = freshInstances }
                if securityGroups != freshGroups { securityGroups = freshGroups }
                if keyPairs != freshKeys { keyPairs = freshKeys }

                // Session restore
                if !hasRestoredSession {
                    if let restoreType = restoreEntityType {
                        entityType = restoreType
                    }
                    if let savedName = restoreEntityName {
                        switch entityType {
                        case .instances:
                            if let inst = instances.first(where: { $0.instanceId == savedName }) {
                                selectedInstanceIDs = [inst.id]
                                selectedInstanceId = inst.instanceId
                            }
                        case .securityGroups:
                            if let sg = securityGroups.first(where: { $0.groupId == savedName }) {
                                selectedGroupIDs = [sg.id]
                                selectedGroupId = sg.groupId
                            }
                        case .keyPairs:
                            if let kp = keyPairs.first(where: { $0.keyName == savedName }) {
                                selectedKeyPairIDs = [kp.id]
                                selectedKeyName = kp.keyName
                            }
                        }
                    }
                    hasRestoredSession = true
                }

                if let name = pendingSelectName {
                    switch entityType {
                    case .instances:
                        if let inst = instances.first(where: { $0.instanceId == name }) {
                            selectedInstanceIDs = [inst.id]
                            selectedInstanceId = inst.instanceId
                        }
                    case .securityGroups:
                        if let sg = securityGroups.first(where: { $0.groupName == name }) {
                            selectedGroupIDs = [sg.id]
                            selectedGroupId = sg.groupId
                        }
                    case .keyPairs:
                        if let kp = keyPairs.first(where: { $0.keyName == name }) {
                            selectedKeyPairIDs = [kp.id]
                            selectedKeyName = kp.keyName
                        }
                    }
                    pendingSelectName = nil
                }
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }

    private func startInstance(_ instance: EC2Instance) {
        Task {
            do {
                try await service.startInstances([instance.instanceId])
                loadEntities(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func stopInstance(_ instance: EC2Instance) {
        Task {
            do {
                try await service.stopInstances([instance.instanceId])
                loadEntities(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func rebootInstance(_ instance: EC2Instance) {
        Task {
            do {
                try await service.rebootInstances([instance.instanceId])
                loadEntities(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func terminateInstances(_ targets: [EC2Instance]) {
        Task {
            do {
                try await service.terminateInstances(targets.map(\.instanceId))
                licenseManager.decrementCreateCount(for: .ec2, by: targets.count)
                selectedInstanceIDs.subtract(Set(targets.map(\.id)))
                if let id = selectedInstanceId, targets.contains(where: { $0.instanceId == id }) {
                    selectedInstanceId = nil
                }
                loadEntities(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteSecurityGroups(_ targets: [EC2SecurityGroup]) {
        Task {
            selectedGroupIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<EC2SecurityGroup.ID> = []
            for sg in targets {
                do {
                    try await service.deleteSecurityGroup(groupId: sg.groupId)
                    deletedIDs.insert(sg.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .ec2, by: deletedIDs.count)
                selectedGroupIDs.subtract(deletedIDs)
                if let id = selectedGroupId, deletedIDs.contains(id) {
                    selectedGroupId = nil
                }
                loadEntities(force: true)
            }
        }
    }

    private func deleteKeyPairs(_ targets: [EC2KeyPair]) {
        Task {
            selectedKeyPairIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<EC2KeyPair.ID> = []
            for kp in targets {
                do {
                    try await service.deleteKeyPair(keyName: kp.keyName)
                    deletedIDs.insert(kp.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .ec2, by: deletedIDs.count)
                selectedKeyPairIDs.subtract(deletedIDs)
                if let name = selectedKeyName, deletedIDs.contains(name) {
                    selectedKeyName = nil
                }
                loadEntities(force: true)
            }
        }
    }
}
