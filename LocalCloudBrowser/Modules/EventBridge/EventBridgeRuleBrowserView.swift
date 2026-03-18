import SwiftUI
import AppKit

struct EventBridgeRuleBrowserView: View {
    @ObservedObject var service: EventBridgeService
    let bus: EventBridgeBus
    @ObservedObject var toolbarState: EventBridgeToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var rules: [EventBridgeRule] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadTime: Date?
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    // Drill-down state
    @State private var activeRule: EventBridgeRule?
    @State private var targets: [EventBridgeTarget] = []
    @State private var isLoadingTargets = false

    // Sheets
    @State private var showDetailSheet = false
    @State private var showCreateRuleSheet = false
    @State private var showPutEventSheet = false
    @State private var showAddTargetSheet = false
    @State private var rulesToDelete: [EventBridgeRule] = []
    @State private var targetsToRemove: [EventBridgeTarget] = []

    var body: some View {
        VStack(spacing: 0) {
            if let rule = activeRule {
                ruleDetailMode(rule: rule)
            } else {
                ruleListMode
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            EventBridgeBusDetailView(bus: bus)
        }
        .sheet(isPresented: $showCreateRuleSheet) {
            EventBridgeCreateRuleView(
                service: service,
                eventBusName: bus.name,
                existingRuleNames: Set(rules.map(\.name))
            )
            .onDisappear { loadRules(force: true) }
        }
        .sheet(isPresented: $showPutEventSheet) {
            EventBridgePutEventView(service: service, eventBusName: bus.name)
        }
        .sheet(isPresented: $showAddTargetSheet) {
            if let rule = activeRule {
                EventBridgeAddTargetView(
                    service: service,
                    ruleName: rule.name,
                    eventBusName: bus.name,
                    currentTargetCount: targets.count
                )
                .onDisappear { loadTargets(ruleName: rule.name) }
            }
        }
        .deleteConfirmation(items: $rulesToDelete, noun: "Rule") { items in
            if items.count == 1, let rule = items.first {
                Text("Are you sure you want to delete \"\(rule.name)\"?\n\nAll targets on this rule will be removed first.")
            } else {
                let names = items.map(\.name).joined(separator: "\n")
                Text("Are you sure you want to delete these rules?\n\n\(names)\n\nThis cannot be undone.")
            }
        } onDelete: { deleteRules($0) }
        .alert(
            "Remove Target",
            isPresented: Binding(
                get: { !targetsToRemove.isEmpty },
                set: { if !$0 { targetsToRemove = [] } }
            )
        ) {
            Button("Remove", role: .destructive) {
                removeTargets(targetsToRemove)
            }
            Button("Cancel", role: .cancel) {
                targetsToRemove = []
            }
        } message: {
            if let target = targetsToRemove.first {
                Text("Are you sure you want to remove target \"\(target.targetId)\"?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadRules() }
        .onAutoRefresh(canRefresh: { activeRule == nil && !showCreateRuleSheet && rulesToDelete.isEmpty && !isLoading }) {
            loadRules(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .viewDetails:
                toolbarState.pendingAction = nil
                showDetailSheet = true
            case .putEvent:
                toolbarState.pendingAction = nil
                showPutEventSheet = true
            case .createRule:
                toolbarState.pendingAction = nil
                showCreateRuleSheet = true
            case .deleteSelected:
                break // handled by bus list
            case .createSchedule, .deleteSelectedGroup:
                break // handled by scheduler views
            }
        }
    }

    private var filteredRules: [EventBridgeRule] {
        guard !searchText.isEmpty else { return rules }
        let query = searchText.lowercased()
        return rules.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Rule List Mode

    @ViewBuilder
    private var ruleListMode: some View {
        // Header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bus.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer()
            ListHeaderButton("plus", isDisabled: appState.isReadOnly, help: "Create Rule") {
                showCreateRuleSheet = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()

        if isLoading && rules.isEmpty {
            ProgressView("Loading rules...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, rules.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadRules(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rules.isEmpty {
            EmptyStateView(icon: "bolt.horizontal", message: "No rules")
            .contextMenu {
                Button("Create Rule") {
                    showCreateRuleSheet = true
                }
                .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if rules.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter rules")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(filteredRules) { rule in
                    Button {
                        drillIntoRule(rule)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    StatusBadge(text: rule.isEnabled ? "ENABLED" : "DISABLED", color: rule.isEnabled ? .green : .gray)
                                    Image(systemName: rule.ruleType.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(rule.ruleType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("View Rule") {
                            drillIntoRule(rule)
                        }
                        Divider()
                        if rule.isEnabled {
                            Button("Disable Rule") {
                                toggleRule(rule, enable: false)
                            }
                            .disabled(appState.isReadOnly)
                        } else {
                            Button("Enable Rule") {
                                toggleRule(rule, enable: true)
                            }
                            .disabled(appState.isReadOnly)
                        }
                        Divider()
                        Button("Copy Name") { copyToClipboard(rule.name) }
                        if let arn = rule.arn {
                            Button("Copy ARN") { copyToClipboard(arn) }
                        }
                        Button("Copy as AWS CLI") {
                            copyToClipboard(rule.describeRuleCLI(endpointUrl: appState.endpoint, region: appState.region))
                        }
                        Divider()
                        Button("Create Rule") {
                            showCreateRuleSheet = true
                        }
                        .disabled(appState.isReadOnly)
                        Divider()
                        Button("Delete", role: .destructive) {
                            rulesToDelete = [rule]
                        }
                        .disabled(appState.isReadOnly)
                    }
                }
                .contextMenu {
                    Button("Create Rule") {
                        showCreateRuleSheet = true
                    }
                    .disabled(appState.isReadOnly)
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Rule Detail Mode

    @ViewBuilder
    private func ruleDetailMode(rule: EventBridgeRule) -> some View {
        // Header with back button
        HStack {
            Button {
                activeRule = nil
                targets = []
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Rules")
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(rule.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if rule.isEnabled {
                Button {
                    toggleRule(rule, enable: false)
                } label: {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(appState.isReadOnly ? .gray : .orange)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Disable Rule")
            } else {
                Button {
                    toggleRule(rule, enable: true)
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(appState.isReadOnly ? .gray : .green)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
                .help("Enable Rule")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        Divider()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ruleInfoSection(rule: rule)
                if let pattern = rule.prettyEventPattern {
                    eventPatternSection(pattern: pattern)
                }
                if let schedule = rule.scheduleExpression {
                    scheduleSection(schedule: schedule)
                }
                targetsSection(rule: rule)
            }
            .padding()
        }

        // Status bar
        Divider()
        HStack {
            if let arn = rule.arn {
                Text(arn)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func ruleInfoSection(rule: EventBridgeRule) -> some View {
        GroupBox("Rule Info") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("State") {
                    StatusBadge(text: rule.state, color: rule.isEnabled ? .green : .gray)
                }
                if let desc = rule.description, !desc.isEmpty {
                    LabeledContent("Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Event Bus") {
                    Text(rule.eventBusName ?? bus.name)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Type") {
                    HStack(spacing: 4) {
                        Image(systemName: rule.ruleType.systemImage)
                            .font(.caption)
                        Text(rule.ruleType.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                if let roleArn = rule.roleArn {
                    LabeledContent("Role ARN") {
                        Text(roleArn)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    @ViewBuilder
    private func eventPatternSection(pattern: String) -> some View {
        GroupBox("Event Pattern") {
            CodeTextEditor(text: .constant(pattern), isEditable: false)
                .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private func scheduleSection(schedule: String) -> some View {
        GroupBox("Schedule") {
            Text(schedule)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }
    }

    @ViewBuilder
    private func targetsSection(rule: EventBridgeRule) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if isLoadingTargets {
                    ProgressView("Loading targets...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if targets.isEmpty {
                    Text("No targets")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(targets) { target in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(target.targetId)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            Text(target.arn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let input = target.prettyInput {
                                Text(input)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button("Copy Target ID") { copyToClipboard(target.targetId) }
                            Button("Copy ARN") { copyToClipboard(target.arn) }
                            Divider()
                            Button("Remove Target", role: .destructive) {
                                targetsToRemove = [target]
                            }
                            .disabled(appState.isReadOnly)
                        }
                    }
                }

                Button {
                    showAddTargetSheet = true
                } label: {
                    Label("Add Target", systemImage: "plus")
                }
                .disabled(appState.isReadOnly || targets.count >= 5)
                .help(targets.count >= 5 ? "Maximum 5 targets per rule" : "Add Target")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack {
                Text("Targets")
                Text("(\(targets.count)/5)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    private func drillIntoRule(_ rule: EventBridgeRule) {
        activeRule = rule
        loadTargets(ruleName: rule.name)
    }

    private func loadRules(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listRules(eventBusName: bus.name)
                let freshRules = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if rules != freshRules {
                    rules = freshRules
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

    private func loadTargets(ruleName: String) {
        isLoadingTargets = true
        Task {
            do {
                targets = try await service.listTargetsByRule(ruleName: ruleName, eventBusName: bus.name)
            } catch {
                serviceError = error.asServiceError
            }
            isLoadingTargets = false
        }
    }

    private func toggleRule(_ rule: EventBridgeRule, enable: Bool) {
        Task {
            do {
                if enable {
                    try await service.enableRule(name: rule.name, eventBusName: bus.name)
                } else {
                    try await service.disableRule(name: rule.name, eventBusName: bus.name)
                }
                // Refresh the rule
                if activeRule != nil {
                    let updated = try await service.describeRule(name: rule.name, eventBusName: bus.name)
                    activeRule = updated
                }
                loadRules(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteRules(_ targets: [EventBridgeRule]) {
        Task {
            for rule in targets {
                do {
                    // Remove all targets first
                    let ruleTargets = try await service.listTargetsByRule(ruleName: rule.name, eventBusName: bus.name)
                    if !ruleTargets.isEmpty {
                        try await service.removeTargets(
                            ruleName: rule.name,
                            eventBusName: bus.name,
                            ids: ruleTargets.map(\.targetId)
                        )
                    }
                    try await service.deleteRule(name: rule.name, eventBusName: bus.name)
                } catch {
                    serviceError = error.asServiceError
                }
            }
            if activeRule != nil {
                activeRule = nil
                self.targets = []
            }
            loadRules(force: true)
        }
    }

    private func removeTargets(_ toRemove: [EventBridgeTarget]) {
        guard let rule = activeRule else { return }
        Task {
            do {
                try await service.removeTargets(
                    ruleName: rule.name,
                    eventBusName: bus.name,
                    ids: toRemove.map(\.targetId)
                )
                loadTargets(ruleName: rule.name)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}
