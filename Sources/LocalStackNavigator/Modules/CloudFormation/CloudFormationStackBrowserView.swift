import SwiftUI
import AppKit

struct CloudFormationStackBrowserView: View {
    @ObservedObject var service: CloudFormationService
    let stack: CloudFormationStack
    @ObservedObject var toolbarState: CloudFormationToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var selectedTab: BrowserTab = .resources
    @State private var resources: [CloudFormationResource] = []
    @State private var events: [CloudFormationEvent] = []
    @State private var detail: CloudFormationStackDetail?
    @State private var isLoadingResources = false
    @State private var isLoadingEvents = false
    @State private var isLoadingDetail = false
    @State private var serviceError: ServiceError?

    // Sheets
    @State private var showDetailSheet = false
    @State private var showTemplateSheet = false

    enum BrowserTab: String, CaseIterable {
        case resources = "Resources"
        case events = "Events"
        case outputs = "Outputs"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            browserHeader
            Divider()

            Picker("Tab", selection: $selectedTab) {
                ForEach(BrowserTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .resources:
                resourcesTab
            case .events:
                eventsTab
            case .outputs:
                outputsTab
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            CloudFormationStackDetailView(service: service, stackName: stack.stackName)
        }
        .sheet(isPresented: $showTemplateSheet) {
            CloudFormationTemplateView(service: service, stackName: stack.stackName)
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadAll() }
        .onChange(of: stack) {
            resources = []
            events = []
            detail = nil
            loadAll()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showDetailSheet && !showTemplateSheet && !isLoadingResources else { return }
            loadResources(silent: true)
            loadEvents(silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .viewDetails:
                toolbarState.pendingAction = nil
                showDetailSheet = true
            case .viewTemplate:
                toolbarState.pendingAction = nil
                showTemplateSheet = true
            case .createStack, .deleteSelected:
                break // handled by list view
            }
        }
    }

    // MARK: - Header

    private var browserHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stack.stackName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(stack.stackStatus)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            stack.statusColor.swiftUIColor.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(stack.statusColor.swiftUIColor)
                    if let created = stack.creationTime {
                        Text("Created: \(Self.dateFormatter.string(from: created))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Resources Tab

    @ViewBuilder
    private var resourcesTab: some View {
        if isLoadingResources && resources.isEmpty {
            ProgressView("Loading resources...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if resources.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No resources")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(resources) { resource in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(resource.shortType)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                            .foregroundStyle(.blue)
                        Text(resource.logicalResourceId)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        Text(resource.resourceStatus)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                resource.statusColor.swiftUIColor.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(resource.statusColor.swiftUIColor)
                    }
                    if let physicalId = resource.physicalResourceId, !physicalId.isEmpty {
                        Text(physicalId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contextMenu {
                    Button("Copy Logical ID") { copyToClipboard(resource.logicalResourceId) }
                    if let physicalId = resource.physicalResourceId {
                        Button("Copy Physical ID") { copyToClipboard(physicalId) }
                    }
                    Button("Copy Type") { copyToClipboard(resource.resourceType) }
                }
            }

            // Status bar
            Divider()
            HStack {
                Text("\(resources.count) resource\(resources.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Events Tab

    @ViewBuilder
    private var eventsTab: some View {
        if isLoadingEvents && events.isEmpty {
            ProgressView("Loading events...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if events.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No events")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let ts = event.timestamp {
                            Text(Self.dateFormatter.string(from: ts))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = event.resourceStatus {
                            Text(status)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    event.statusColor.swiftUIColor.opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(event.statusColor.swiftUIColor)
                        }
                    }
                    HStack(spacing: 6) {
                        if let type = event.resourceType {
                            Text(type)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        if let logicalId = event.logicalResourceId {
                            Text(logicalId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let reason = event.resourceStatusReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                .contextMenu {
                    if let logicalId = event.logicalResourceId {
                        Button("Copy Logical ID") { copyToClipboard(logicalId) }
                    }
                    if let physicalId = event.physicalResourceId {
                        Button("Copy Physical ID") { copyToClipboard(physicalId) }
                    }
                    Button("Copy Event ID") { copyToClipboard(event.eventId) }
                }
            }

            // Status bar
            Divider()
            HStack {
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Outputs Tab

    @ViewBuilder
    private var outputsTab: some View {
        if isLoadingDetail && detail == nil {
            ProgressView("Loading stack details...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !detail.outputs.isEmpty {
                        GroupBox("Outputs") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(detail.outputs) { output in
                                    VStack(alignment: .leading, spacing: 2) {
                                        LabeledContent(output.outputKey) {
                                            CopyableValue(text: output.outputValue, monospaced: true)
                                        }
                                        if let desc = output.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let exportName = output.exportName, !exportName.isEmpty {
                                            Text("Export: \(exportName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                        }
                    } else {
                        GroupBox("Outputs") {
                            Text("No outputs")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(4)
                        }
                    }

                    if !detail.parameters.isEmpty {
                        GroupBox("Parameters") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(detail.parameters) { param in
                                    LabeledContent(param.parameterKey) {
                                        CopyableValue(text: param.parameterValue, monospaced: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                        }
                    }
                }
                .padding()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No details available")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Data

    private func loadAll() {
        loadResources()
        loadEvents()
        loadDetail()
    }

    private func loadResources(silent: Bool = false) {
        if !silent { isLoadingResources = true }
        Task {
            do {
                resources = try await service.listStackResources(name: stack.stackName)
            } catch {
                if !silent { serviceError = error.asServiceError }
            }
            if !silent { isLoadingResources = false }
        }
    }

    private func loadEvents(silent: Bool = false) {
        if !silent { isLoadingEvents = true }
        Task {
            do {
                let loaded = try await service.describeStackEvents(name: stack.stackName)
                // Sort newest first
                events = loaded.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            } catch {
                if !silent { serviceError = error.asServiceError }
            }
            if !silent { isLoadingEvents = false }
        }
    }

    private func loadDetail() {
        isLoadingDetail = true
        Task {
            do {
                detail = try await service.describeStack(name: stack.stackName)
            } catch {
                // Non-critical — outputs tab will show placeholder
            }
            isLoadingDetail = false
        }
    }
}
