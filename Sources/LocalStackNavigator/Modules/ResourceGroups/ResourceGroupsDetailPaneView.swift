import SwiftUI
import AppKit

struct ResourceGroupsDetailPaneView: View {
    @ObservedObject var service: ResourceGroupsService
    let group: ResourceGroupSummary
    @EnvironmentObject private var appState: AppState

    @State private var query: ResourceGroupQuery?
    @State private var resources: [GroupResource] = []
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && query == nil {
                ProgressView("Loading group details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summarySection
                        querySection
                        resourcesSection
                    }
                    .padding(16)
                }
            }
        }
        .task { loadDetails() }
        .onChange(of: group.name) {
            query = nil
            resources = []
            loadDetails()
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !isLoading else { return }
            loadDetails(silent: true)
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        GroupBox("Summary") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Name") {
                    CopyableValue(text: group.name)
                }
                if !group.groupArn.isEmpty {
                    labeledRow("ARN") {
                        CopyableValue(text: group.groupArn, font: .caption, monospaced: true)
                    }
                }
                if !group.description.isEmpty {
                    labeledRow("Description") {
                        Text(group.description)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Query Section

    private var querySection: some View {
        GroupBox {
            if let query {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow("Type") {
                        Text(query.type)
                            .font(.body.monospaced())
                    }
                    if !query.tagFilters.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tag Filters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .trailing)
                            ForEach(query.tagFilters) { filter in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(filter.key)
                                        .fontWeight(.medium)
                                        .font(.body.monospaced())
                                    if !filter.values.isEmpty {
                                        Text(filter.values.joined(separator: ", "))
                                            .foregroundStyle(.secondary)
                                            .font(.body.monospaced())
                                    } else {
                                        Text("(any value)")
                                            .foregroundStyle(.tertiary)
                                            .italic()
                                    }
                                }
                                .padding(.leading, 112)
                            }
                        }
                    }
                    if !query.resourceTypeFilters.isEmpty {
                        labeledRow("Resources") {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(query.resourceTypeFilters, id: \.self) { type in
                                    Text(type)
                                        .font(.body.monospaced())
                                }
                            }
                        }
                    }
                }
                .padding(4)
            } else {
                Text("Loading query...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        } label: {
            Text("Query")
        }
    }

    // MARK: - Resources Section

    private var resourcesSection: some View {
        GroupBox {
            if resources.isEmpty && !isLoading {
                Text("No matched resources")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(resources) { resource in
                        HStack(spacing: 8) {
                            resourceTypeBadge(resource)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.resourceArn)
                                    .font(.body.monospaced())
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                                Text(resource.shortTypeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !resource.status.isEmpty {
                                Text(resource.status)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        .contextMenu {
                            Button("Copy ARN") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(resource.resourceArn, forType: .string)
                            }
                            Button("Copy Resource Type") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(resource.resourceType, forType: .string)
                            }
                        }
                        if resource.id != resources.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(4)
            }
        } label: {
            HStack {
                Text("Matched Resources")
                if !resources.isEmpty {
                    Text("(\(resources.count))")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func resourceTypeBadge(_ resource: GroupResource) -> some View {
        let info = resource.typeColor
        let color = badgeColor(info.color)
        return Text(info.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func badgeColor(_ name: String) -> Color {
        switch name {
        case "green": .green
        case "orange": .orange
        case "blue": .blue
        case "purple": .purple
        case "teal": .teal
        case "pink": .pink
        case "indigo": .indigo
        case "brown": .brown
        default: .gray
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadDetails(silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                async let queryResult = service.getGroupQuery(name: group.name)
                async let resourcesResult = service.listGroupResources(name: group.name)

                let loadedQuery = try await queryResult
                let loadedResources = try await resourcesResult

                query = loadedQuery
                resources = loadedResources
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }
}
