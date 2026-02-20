import SwiftUI
import AppKit

struct Route53ResolverListView: View {
    @ObservedObject var service: Route53ResolverService
    @ObservedObject var toolbarState: Route53ToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var selectedEndpointIDs: Set<ResolverEndpoint.ID>
    @Binding var activeEndpoint: ResolverEndpoint?
    var restoreEndpointId: String?

    @State private var rules: [ResolverRule] = []
    @State private var pendingSelectName: String?
    @State private var showCreateEndpointSheet = false
    @State private var showCreateRuleSheet = false
    @State private var endpointsToDelete: [ResolverEndpoint] = []
    @State private var rulesToDelete: [ResolverRule] = []
    @State private var serviceError: ServiceError?
    @State private var searchText = ""
    @StateObject private var loader = ListLoader<ResolverEndpoint>()
    private var endpoints: [ResolverEndpoint] { loader.items }

    var body: some View {
        VStack(spacing: 0) {
            listContent
        }
        .sheet(isPresented: $showCreateEndpointSheet) {
            Route53ResolverCreateEndpointView(service: service) { name in
                pendingSelectName = name
            }
            .onDisappear { loadData(force: true) }
        }
        .sheet(isPresented: $showCreateRuleSheet) {
            Route53ResolverCreateRuleView(service: service)
                .onDisappear { loadData(force: true) }
        }
        .deleteConfirmation(items: $endpointsToDelete, title: { _ in "Delete Resolver Endpoint" }, actionLabel: "Delete") { items in
            if let ep = items.first {
                Text("Are you sure you want to delete resolver endpoint \"\(ep.name)\"?\n\nThis action cannot be undone.")
            }
        } onDelete: { deleteEndpoints($0) }
        .deleteConfirmation(items: $rulesToDelete, title: { _ in "Delete Resolver Rule" }, actionLabel: "Delete") { items in
            if let rule = items.first {
                Text("Are you sure you want to delete resolver rule \"\(rule.name)\"?\n\nThis action cannot be undone.")
            }
        } onDelete: { deleteRules($0) }
        .serviceErrorAlert(error: $serviceError)
        .task { loadData() }
        .onAutoRefresh(canRefresh: { !showCreateEndpointSheet && !showCreateRuleSheet &&
                  endpointsToDelete.isEmpty && rulesToDelete.isEmpty && !loader.isLoading }) {
            loadData(force: true, silent: true)
        }
        .resetOnConnectionChange {
            selectedEndpointIDs = []
            activeEndpoint = nil
            loader.items = []
            rules = []
            loadData(force: true)
        }
        .syncSelection(selectedEndpointIDs, items: endpoints, activeItem: $activeEndpoint)
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createEndpoint:
                toolbarState.pendingAction = nil
                showCreateEndpointSheet = true
            case .createRule:
                toolbarState.pendingAction = nil
                showCreateRuleSheet = true
            case .deleteEndpoint:
                toolbarState.pendingAction = nil
                if let active = activeEndpoint {
                    endpointsToDelete = [active]
                }
            case .createZone, .createRecord, .deleteZone:
                break
            }
        }
    }

    private var filteredEndpoints: [ResolverEndpoint] {
        guard !searchText.isEmpty else { return endpoints }
        let query = searchText.lowercased()
        return endpoints.filter {
            $0.name.lowercased().contains(query) ||
            $0.id.lowercased().contains(query)
        }
    }

    private var filteredRules: [ResolverRule] {
        guard !searchText.isEmpty else { return rules }
        let query = searchText.lowercased()
        return rules.filter {
            $0.name.lowercased().contains(query) ||
            $0.domainName.lowercased().contains(query)
        }
    }

    // MARK: - Content

    private var listContent: some View {
        ListLoadingContent(isLoading: loader.isLoading, isEmpty: endpoints.isEmpty && rules.isEmpty, errorMessage: loader.errorMessage, loadingMessage: "Loading resolver...", onRetry: { loadData(force: true) }) {
            if endpoints.isEmpty && rules.isEmpty {
                EmptyStateView(icon: "network", message: "No resolver endpoints or rules")
                .contextMenu {
                    Button("Create Endpoint") {
                        showCreateEndpointSheet = true
                    }
                    .disabled(appState.isReadOnly)
                    Button("Create Rule") {
                        showCreateRuleSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }
            } else {
                VStack(spacing: 0) {
                    if endpoints.count + rules.count > 5 {
                        SearchBarView(query: $searchText, placeholder: "Filter endpoints & rules")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        Divider()
                    }
                    List(selection: $selectedEndpointIDs) {
                        if !filteredEndpoints.isEmpty {
                            Section("Endpoints") {
                                ForEach(filteredEndpoints) { endpoint in
                                    endpointRow(endpoint)
                                        .selectionForeground()
                                        .tag(endpoint.id)
                                }
                            }
                        }
                        if !filteredRules.isEmpty {
                            Section("Rules") {
                                ForEach(filteredRules) { rule in
                                    ruleRow(rule)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if loader.errorMessage != nil {
                            ConnectionLostBanner()
                        }
                    }
                    .contextMenu {
                        Button("Create Endpoint") {
                            showCreateEndpointSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Button("Create Rule") {
                            showCreateRuleSheet = true
                        }
                        .disabled(appState.isReadOnly)
                    }

                    // Status bar
                    Divider()
                    HStack {
                        Text("\(endpoints.count) endpoint\(endpoints.count == 1 ? "" : "s"), \(rules.count) rule\(rules.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Rows

    private func endpointRow(_ endpoint: ResolverEndpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name.isEmpty ? endpoint.id : endpoint.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !endpoint.name.isEmpty {
                    Text(endpoint.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            directionBadge(endpoint.direction)
            statusBadge(endpoint.status, color: endpoint.statusBadgeColor)
        }
        .contextMenu {
            Button("Copy Name") { copyToClipboard(endpoint.name) }
            Button("Copy ID") { copyToClipboard(endpoint.id) }
            Button("Copy ARN") { copyToClipboard(endpoint.arn) }
            Menu("Copy as AWS CLI") {
                Button("Describe Endpoint") {
                    copyToClipboard(endpoint.describeCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
                Button("List Endpoints") {
                    copyToClipboard(ResolverEndpoint.listCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
                Button("Delete Endpoint") {
                    copyToClipboard(endpoint.deleteCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
            }
            Divider()
            Button("Create Endpoint") {
                showCreateEndpointSheet = true
            }
            .disabled(appState.isReadOnly)
            Divider()
            Button("Delete", role: .destructive) {
                endpointsToDelete = [endpoint]
            }
            .disabled(appState.isReadOnly)
        }
    }

    private func ruleRow(_ rule: ResolverRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? rule.id : rule.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(rule.domainName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            ruleTypeBadge(rule.ruleType)
            statusBadge(rule.status, color: rule.statusBadgeColor)
        }
        .contextMenu {
            Button("Copy Name") { copyToClipboard(rule.name) }
            Button("Copy ID") { copyToClipboard(rule.id) }
            Button("Copy Domain") { copyToClipboard(rule.domainName) }
            Menu("Copy as AWS CLI") {
                Button("Describe Rule") {
                    copyToClipboard(rule.describeCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
                Button("List Rules") {
                    copyToClipboard(ResolverRule.listCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
                Button("Delete Rule") {
                    copyToClipboard(rule.deleteCLI(endpointUrl: appState.endpoint, region: appState.region))
                }
            }
            Divider()
            Button("Create Rule") {
                showCreateRuleSheet = true
            }
            .disabled(appState.isReadOnly)
            Divider()
            if rule.ruleType != "SYSTEM" {
                Button("Delete", role: .destructive) {
                    rulesToDelete = [rule]
                }
                .disabled(appState.isReadOnly)
            }
        }
    }

    // MARK: - Badges

    private func statusBadge(_ status: String, color: Color) -> some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func directionBadge(_ direction: String) -> some View {
        let color: Color = direction == "INBOUND" ? .blue : .purple
        return Text(direction)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func ruleTypeBadge(_ type: String) -> some View {
        let color: Color = switch type {
        case "FORWARD": .blue
        case "RECURSIVE": .purple
        default: .gray
        }
        return Text(type)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Data

    private func loadData(force: Bool = false, silent: Bool = false) {
        loader.load(force: force, silent: silent,
            fetch: { [service] in try await service.listResolverEndpoints() },
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ) { [self] items in
            if let freshRules = try? await service.listResolverRules() {
                let sorted = freshRules.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if rules != sorted { rules = sorted }
            }
            if !loader.hasRestoredSession, let savedId = restoreEndpointId,
               let ep = items.first(where: { $0.id == savedId }) {
                selectedEndpointIDs = [ep.id]
                activeEndpoint = ep
            }
            loader.hasRestoredSession = true
            if let name = pendingSelectName,
               let ep = items.first(where: { $0.name == name }) {
                selectedEndpointIDs = [ep.id]
                activeEndpoint = ep
                pendingSelectName = nil
            }
        }
    }

    private func deleteEndpoints(_ targets: [ResolverEndpoint]) {
        Task {
            let (deletedIDs, lastError) = await batchDelete(targets) { ep in
                try await service.deleteResolverEndpoint(id: ep.id)
            }
            if let lastError { serviceError = lastError }
            if !deletedIDs.isEmpty {
                selectedEndpointIDs.subtract(deletedIDs)
                if let active = activeEndpoint, deletedIDs.contains(active.id) {
                    activeEndpoint = nil
                }
                loadData(force: true)
            }
        }
    }

    private func deleteRules(_ targets: [ResolverRule]) {
        Task {
            let (_, lastError) = await batchDelete(targets) { rule in
                try await service.deleteResolverRule(id: rule.id)
            }
            if let lastError { serviceError = lastError }
            loadData(force: true)
        }
    }
}
