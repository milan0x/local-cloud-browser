import SwiftUI
import AppKit

struct IAMEntityListView: View {
    @ObservedObject var service: IAMService
    @ObservedObject var toolbarState: IAMToolbarState
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var licenseManager: LicenseManager
    @Binding var entityType: IAMEntityType
    @Binding var selectedUserName: String?
    @Binding var selectedRoleName: String?
    @Binding var selectedPolicyArn: String?
    var restoreEntityType: IAMEntityType?
    var restoreEntityName: String?

    @StateObject private var userLoader = PaginatedListLoader<IAMUser>()
    @StateObject private var roleLoader = PaginatedListLoader<IAMRole>()
    @StateObject private var policyLoader = PaginatedListLoader<IAMPolicy>()
    private var users: [IAMUser] { userLoader.items }
    private var roles: [IAMRole] { roleLoader.items }
    private var policies: [IAMPolicy] { policyLoader.items }
    private var isLoading: Bool { userLoader.isLoading || roleLoader.isLoading || policyLoader.isLoading }
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    // Create sheets
    @State private var showCreateUserSheet = false
    @State private var showCreateRoleSheet = false
    @State private var showCreatePolicySheet = false
    @State private var pendingSelectName: String?

    // Delete
    @State private var usersToDelete: [IAMUser] = []
    @State private var rolesToDelete: [IAMRole] = []
    @State private var policiesToDelete: [IAMPolicy] = []

    // Selection tracking
    @State private var selectedUserIDs: Set<IAMUser.ID> = []
    @State private var selectedRoleIDs: Set<IAMRole.ID> = []
    @State private var selectedPolicyIDs: Set<IAMPolicy.ID> = []

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

            SegmentedTabPicker(selection: $entityType)

            Divider()
            listContent
        }
        // Create sheets
        .sheet(isPresented: $showCreateUserSheet) {
            IAMCreateUserView(service: service, existingUserNames: Set(users.map(\.userName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadEntities(force: true) }
        }
        .sheet(isPresented: $showCreateRoleSheet) {
            IAMCreateRoleView(service: service, existingRoleNames: Set(roles.map(\.roleName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadEntities(force: true) }
        }
        .sheet(isPresented: $showCreatePolicySheet) {
            IAMCreatePolicyView(service: service, existingPolicyNames: Set(policies.map(\.policyName))) { name in
                pendingSelectName = name
            }
            .onDisappear { loadEntities(force: true) }
        }
        // Delete alerts
        .alert(
            usersToDelete.count == 1 ? "Delete User" : "Delete \(usersToDelete.count) Users",
            isPresented: Binding(get: { !usersToDelete.isEmpty }, set: { if !$0 { usersToDelete = [] } })
        ) {
            Button("Delete", role: .destructive) { deleteUsers(usersToDelete) }
            Button("Cancel", role: .cancel) { usersToDelete = [] }
        } message: {
            if usersToDelete.count == 1, let user = usersToDelete.first {
                Text("Are you sure you want to delete user \"\(user.userName)\"?\n\nAll attached policies and group memberships will be removed.")
            } else {
                Text("Are you sure you want to delete \(usersToDelete.count) users?\n\nThis cannot be undone.")
            }
        }
        .alert(
            rolesToDelete.count == 1 ? "Delete Role" : "Delete \(rolesToDelete.count) Roles",
            isPresented: Binding(get: { !rolesToDelete.isEmpty }, set: { if !$0 { rolesToDelete = [] } })
        ) {
            Button("Delete", role: .destructive) { deleteRoles(rolesToDelete) }
            Button("Cancel", role: .cancel) { rolesToDelete = [] }
        } message: {
            if rolesToDelete.count == 1, let role = rolesToDelete.first {
                Text("Are you sure you want to delete role \"\(role.roleName)\"?\n\nAll attached policies will be detached.")
            } else {
                Text("Are you sure you want to delete \(rolesToDelete.count) roles?\n\nThis cannot be undone.")
            }
        }
        .alert(
            policiesToDelete.count == 1 ? "Delete Policy" : "Delete \(policiesToDelete.count) Policies",
            isPresented: Binding(get: { !policiesToDelete.isEmpty }, set: { if !$0 { policiesToDelete = [] } })
        ) {
            Button("Delete", role: .destructive) { deletePolicies(policiesToDelete) }
            Button("Cancel", role: .cancel) { policiesToDelete = [] }
        } message: {
            if policiesToDelete.count == 1, let policy = policiesToDelete.first {
                Text("Are you sure you want to delete policy \"\(policy.policyName)\"?")
            } else {
                Text("Are you sure you want to delete \(policiesToDelete.count) policies?\n\nThis cannot be undone.")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadEntities() }
        .onAutoRefresh(canRefresh: { !showCreateUserSheet && !showCreateRoleSheet && !showCreatePolicySheet && !isLoading }) {
            loadEntities(force: true, silent: true)
        }
        .resetOnConnectionChange {
            clearAllSelections()
            loadEntities(force: true)
        }
        .onChange(of: entityType) {
            searchText = ""
        }
        .onChange(of: selectedUserIDs) {
            if selectedUserIDs.count == 1, let id = selectedUserIDs.first {
                selectedUserName = id
            } else {
                selectedUserName = nil
            }
        }
        .onChange(of: selectedRoleIDs) {
            if selectedRoleIDs.count == 1, let id = selectedRoleIDs.first {
                selectedRoleName = id
            } else {
                selectedRoleName = nil
            }
        }
        .onChange(of: selectedPolicyIDs) {
            if selectedPolicyIDs.count == 1, let id = selectedPolicyIDs.first {
                selectedPolicyArn = id
            } else {
                selectedPolicyArn = nil
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
        selectedUserIDs = []
        selectedRoleIDs = []
        selectedPolicyIDs = []
        selectedUserName = nil
        selectedRoleName = nil
        selectedPolicyArn = nil
        userLoader.items = []
        roleLoader.items = []
        policyLoader.items = []
    }

    // MARK: - Header

    private var listHeader: some View {
        ListHeaderBar(
            title: "IAM",
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
        case .users: return users.count
        case .roles: return roles.count
        case .policies: return policies.count
        }
    }

    private var deleteDisabled: Bool {
        if appState.isReadOnly { return true }
        switch entityType {
        case .users: return selectedUserIDs.isEmpty
        case .roles: return selectedRoleIDs.isEmpty
        case .policies: return selectedPolicyIDs.isEmpty
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        switch entityType {
        case .users: usersListContent
        case .roles: rolesListContent
        case .policies: policiesListContent
        }
    }

    // MARK: - Users List

    private var filteredUsers: [IAMUser] {
        guard !searchText.isEmpty else { return users }
        let query = searchText.lowercased()
        return users.filter { $0.userName.lowercased().contains(query) }
    }

    @ViewBuilder
    private var usersListContent: some View {
        if isLoading && users.isEmpty {
            ProgressView("Loading users...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = userLoader.errorMessage, users.isEmpty {
            errorView(errorMessage)
        } else if users.isEmpty {
            emptyView("No users", icon: "person")
        } else {
            VStack(spacing: 0) {
                if users.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter users")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredUsers, selection: $selectedUserIDs) { user in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.userName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let created = user.createDate {
                            Text(Self.dateFormatter.string(from: created))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .selectionForeground()
                    .tag(user.id)
                    .contextMenu { userContextMenu(user) }
                }
                .contextMenu { createContextMenu }

                if userLoader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            userLoader.loadMore()
                        } label: {
                            if userLoader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(userLoader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredUsers.isEmpty && !searchText.isEmpty && userLoader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            userLoader.searchAll { $0.userName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if userLoader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if userLoader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                ListStatusBar(totalCount: users.count, selectedCount: selectedUserIDs.count, noun: "user", hasMorePages: userLoader.hasMorePages)
            }
        }
    }

    @ViewBuilder
    private func userContextMenu(_ user: IAMUser) -> some View {
        Button("Copy Name") { copyToClipboard(user.userName) }
        if let arn = user.arn {
            Button("Copy ARN") { copyToClipboard(arn) }
        }
        Button("Copy as AWS CLI") {
            copyToClipboard(user.getUserCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Create User") { showCreateUserSheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if selectedUserIDs.count > 1 && selectedUserIDs.contains(user.id) {
            let selected = users.filter { selectedUserIDs.contains($0.id) }
            Button("Delete \(selected.count) Users", role: .destructive) { usersToDelete = selected }
                .disabled(appState.isReadOnly)
        } else {
            Button("Delete", role: .destructive) { usersToDelete = [user] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Roles List

    private var filteredRoles: [IAMRole] {
        guard !searchText.isEmpty else { return roles }
        let query = searchText.lowercased()
        return roles.filter { $0.roleName.lowercased().contains(query) }
    }

    @ViewBuilder
    private var rolesListContent: some View {
        if isLoading && roles.isEmpty {
            ProgressView("Loading roles...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = roleLoader.errorMessage, roles.isEmpty {
            errorView(errorMessage)
        } else if roles.isEmpty {
            emptyView("No roles", icon: "person.badge.key")
        } else {
            VStack(spacing: 0) {
                if roles.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter roles")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredRoles, selection: $selectedRoleIDs) { role in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(role.roleName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if let desc = role.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let created = role.createDate {
                            Text(Self.dateFormatter.string(from: created))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .selectionForeground()
                    .tag(role.id)
                    .contextMenu { roleContextMenu(role) }
                }
                .contextMenu { createContextMenu }

                if roleLoader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            roleLoader.loadMore()
                        } label: {
                            if roleLoader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(roleLoader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredRoles.isEmpty && !searchText.isEmpty && roleLoader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            roleLoader.searchAll { $0.roleName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if roleLoader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if roleLoader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                ListStatusBar(totalCount: roles.count, selectedCount: selectedRoleIDs.count, noun: "role", hasMorePages: roleLoader.hasMorePages)
            }
        }
    }

    @ViewBuilder
    private func roleContextMenu(_ role: IAMRole) -> some View {
        Button("Copy Name") { copyToClipboard(role.roleName) }
        if let arn = role.arn {
            Button("Copy ARN") { copyToClipboard(arn) }
        }
        Button("Copy as AWS CLI") {
            copyToClipboard(role.getRoleCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Create Role") { showCreateRoleSheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if selectedRoleIDs.count > 1 && selectedRoleIDs.contains(role.id) {
            let selected = roles.filter { selectedRoleIDs.contains($0.id) }
            Button("Delete \(selected.count) Roles", role: .destructive) { rolesToDelete = selected }
                .disabled(appState.isReadOnly)
        } else {
            Button("Delete", role: .destructive) { rolesToDelete = [role] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Policies List

    private var filteredPolicies: [IAMPolicy] {
        guard !searchText.isEmpty else { return policies }
        let query = searchText.lowercased()
        return policies.filter { $0.policyName.lowercased().contains(query) }
    }

    @ViewBuilder
    private var policiesListContent: some View {
        if isLoading && policies.isEmpty {
            ProgressView("Loading policies...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = policyLoader.errorMessage, policies.isEmpty {
            errorView(errorMessage)
        } else if policies.isEmpty {
            emptyView("No policies", icon: "doc.text")
        } else {
            VStack(spacing: 0) {
                if policies.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter policies")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredPolicies, selection: $selectedPolicyIDs) { policy in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(policy.policyName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if policy.attachmentCount > 0 {
                                Text("\(policy.attachmentCount) attached")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let created = policy.createDate {
                                Text(Self.dateFormatter.string(from: created))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .selectionForeground()
                    .tag(policy.id)
                    .contextMenu { policyContextMenu(policy) }
                }
                .contextMenu { createContextMenu }

                if policyLoader.hasMorePages {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            policyLoader.loadMore()
                        } label: {
                            if policyLoader.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Loading...")
                            } else {
                                Text("Load More")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(policyLoader.isLoadingMore)
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                if filteredPolicies.isEmpty && !searchText.isEmpty && policyLoader.hasMorePages {
                    VStack(spacing: 6) {
                        Text("No matches in loaded items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Search all items") {
                            let query = searchText.lowercased()
                            policyLoader.searchAll { $0.policyName.lowercased().contains(query) }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        if policyLoader.isSearchingAll {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if policyLoader.searchAllHitCap {
                    Text("Showing results from first 10,000 items. Refine your search for better results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                ListStatusBar(totalCount: policies.count, selectedCount: selectedPolicyIDs.count, noun: "policy", pluralNoun: "policies", hasMorePages: policyLoader.hasMorePages)
            }
        }
    }

    @ViewBuilder
    private func policyContextMenu(_ policy: IAMPolicy) -> some View {
        Button("Copy Name") { copyToClipboard(policy.policyName) }
        Button("Copy ARN") { copyToClipboard(policy.arn) }
        Button("Copy as AWS CLI") {
            copyToClipboard(policy.getPolicyCLI(endpointUrl: appState.endpoint, region: appState.region))
        }
        Divider()
        Button("Create Policy") { showCreatePolicySheet = true }
            .disabled(appState.isReadOnly)
        Divider()
        if selectedPolicyIDs.count > 1 && selectedPolicyIDs.contains(policy.id) {
            let selected = policies.filter { selectedPolicyIDs.contains($0.id) }
            Button("Delete \(selected.count) Policies", role: .destructive) { policiesToDelete = selected }
                .disabled(appState.isReadOnly)
        } else {
            Button("Delete", role: .destructive) { policiesToDelete = [policy] }
                .disabled(appState.isReadOnly)
        }
    }

    // MARK: - Shared Views

    @ViewBuilder
    private var createContextMenu: some View {
        switch entityType {
        case .users:
            Button("Create User") { showCreateUserSheet = true }
                .disabled(appState.isReadOnly)
        case .roles:
            Button("Create Role") { showCreateRoleSheet = true }
                .disabled(appState.isReadOnly)
        case .policies:
            Button("Create Policy") { showCreatePolicySheet = true }
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
        case .users: showCreateUserSheet = true
        case .roles: showCreateRoleSheet = true
        case .policies: showCreatePolicySheet = true
        }
    }

    private func deleteCurrentSelection() {
        switch entityType {
        case .users:
            let selected = users.filter { selectedUserIDs.contains($0.id) }
            if !selected.isEmpty { usersToDelete = selected }
        case .roles:
            let selected = roles.filter { selectedRoleIDs.contains($0.id) }
            if !selected.isEmpty { rolesToDelete = selected }
        case .policies:
            let selected = policies.filter { selectedPolicyIDs.contains($0.id) }
            if !selected.isEmpty { policiesToDelete = selected }
        }
    }

    // MARK: - Data

    @State private var hasRestoredSession = false

    private func loadEntities(force: Bool = false, silent: Bool = false) {
        // Restore entity type once before loads start to avoid race condition
        // where multiple loader callbacks each try to restore session state
        if !hasRestoredSession {
            hasRestoredSession = true
            if let restoreType = restoreEntityType { entityType = restoreType }
        }
        loadUsers(force: force, silent: silent)
        loadRoles(force: force, silent: silent)
        loadPolicies(force: force, silent: silent)
    }

    private func loadUsers(force: Bool = false, silent: Bool = false) {
        userLoader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listUsersPage(token: token) },
            sort: { $0.userName.localizedStandardCompare($1.userName) == .orderedAscending }
        ) { [self] items in
            if let savedName = restoreEntityName, entityType == .users,
               let user = items.first(where: { $0.userName == savedName }) {
                if selectedUserIDs.isEmpty {
                    selectedUserIDs = [user.id]
                    selectedUserName = user.userName
                }
            }
            if let name = pendingSelectName, entityType == .users,
               let user = items.first(where: { $0.userName == name }) {
                selectedUserIDs = [user.id]
                selectedUserName = user.userName
                pendingSelectName = nil
            }
        }
    }

    private func loadRoles(force: Bool = false, silent: Bool = false) {
        roleLoader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listRolesPage(token: token) },
            sort: { $0.roleName.localizedStandardCompare($1.roleName) == .orderedAscending }
        ) { [self] items in
            if let savedName = restoreEntityName, entityType == .roles,
               let role = items.first(where: { $0.roleName == savedName }) {
                if selectedRoleIDs.isEmpty {
                    selectedRoleIDs = [role.id]
                    selectedRoleName = role.roleName
                }
            }
            if let name = pendingSelectName, entityType == .roles,
               let role = items.first(where: { $0.roleName == name }) {
                selectedRoleIDs = [role.id]
                selectedRoleName = role.roleName
                pendingSelectName = nil
            }
        }
    }

    private func loadPolicies(force: Bool = false, silent: Bool = false) {
        policyLoader.load(force: force, silent: silent,
            fetch: { [service] token in try await service.listPoliciesPage(scope: "Local", token: token) },
            sort: { $0.policyName.localizedStandardCompare($1.policyName) == .orderedAscending }
        ) { [self] items in
            if let savedName = restoreEntityName, entityType == .policies,
               let policy = items.first(where: { $0.arn == savedName }) {
                if selectedPolicyIDs.isEmpty {
                    selectedPolicyIDs = [policy.id]
                    selectedPolicyArn = policy.arn
                }
            }
            if let name = pendingSelectName, entityType == .policies,
               let policy = items.first(where: { $0.policyName == name }) {
                selectedPolicyIDs = [policy.id]
                selectedPolicyArn = policy.arn
                pendingSelectName = nil
            }
        }
    }

    private func deleteUsers(_ targets: [IAMUser]) {
        Task {
            selectedUserIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<IAMUser.ID> = []
            for user in targets {
                do {
                    try await service.deleteUser(userName: user.userName)
                    deletedIDs.insert(user.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .iam, by: deletedIDs.count)
                selectedUserIDs.subtract(deletedIDs)
                if let name = selectedUserName, deletedIDs.contains(name) {
                    selectedUserName = nil
                }
                loadEntities(force: true)
            }
        }
    }

    private func deleteRoles(_ targets: [IAMRole]) {
        Task {
            selectedRoleIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<IAMRole.ID> = []
            for role in targets {
                do {
                    try await service.deleteRole(roleName: role.roleName)
                    deletedIDs.insert(role.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .iam, by: deletedIDs.count)
                selectedRoleIDs.subtract(deletedIDs)
                if let name = selectedRoleName, deletedIDs.contains(name) {
                    selectedRoleName = nil
                }
                loadEntities(force: true)
            }
        }
    }

    private func deletePolicies(_ targets: [IAMPolicy]) {
        Task {
            selectedPolicyIDs.subtract(Set(targets.map(\.id)))
            var deletedIDs: Set<IAMPolicy.ID> = []
            for policy in targets {
                do {
                    try await service.deletePolicy(policyArn: policy.arn)
                    deletedIDs.insert(policy.id)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if !deletedIDs.isEmpty {
                licenseManager.decrementCreateCount(for: .iam, by: deletedIDs.count)
                selectedPolicyIDs.subtract(deletedIDs)
                if let arn = selectedPolicyArn, deletedIDs.contains(arn) {
                    selectedPolicyArn = nil
                }
                loadEntities(force: true)
            }
        }
    }
}
