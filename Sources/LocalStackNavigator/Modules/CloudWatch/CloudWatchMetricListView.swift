import SwiftUI
import AppKit

struct CloudWatchMetricListView: View {
    @ObservedObject var service: CloudWatchService
    @ObservedObject var toolbarState: CloudWatchToolbarState
    @EnvironmentObject private var appState: AppState
    @Binding var activeMetric: CloudWatchMetric?

    @State private var metrics: [CloudWatchMetric] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastLoadTime: Date?
    @State private var searchText = ""
    @State private var serviceError: ServiceError?
    @State private var showPutMetricSheet = false

    /// Metrics grouped by namespace, sorted by namespace.
    private var groupedMetrics: [(namespace: String, metrics: [CloudWatchMetric])] {
        let filtered: [CloudWatchMetric]
        if searchText.isEmpty {
            filtered = metrics
        } else {
            let query = searchText.lowercased()
            filtered = metrics.filter {
                $0.namespace.lowercased().contains(query) ||
                $0.metricName.lowercased().contains(query)
            }
        }
        let grouped = Dictionary(grouping: filtered, by: \.namespace)
        return grouped
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { (namespace: $0.key, metrics: $0.value.sorted { $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            listContent
        }
        .sheet(isPresented: $showPutMetricSheet) {
            CloudWatchPutMetricView(service: service)
                .onDisappear { loadMetrics(force: true) }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadMetrics() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showPutMetricSheet && !isLoading else { return }
            loadMetrics(force: true, silent: true)
        }
        .onChange(of: appState.connectionVersion) {
            activeMetric = nil
            metrics = []
            loadMetrics(force: true)
        }
        .onChange(of: appState.region) {
            activeMetric = nil
            metrics = []
            loadMetrics(force: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            if action == .putMetric {
                toolbarState.pendingAction = nil
                showPutMetricSheet = true
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var listContent: some View {
        if isLoading && metrics.isEmpty {
            VStack(spacing: 12) {
                ProgressView("Loading metrics...")
                if appState.connectionError != nil {
                    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, metrics.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadMetrics(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if metrics.isEmpty {
            EmptyStateView(icon: "chart.xyaxis.line", message: "No metrics", secondaryMessage: "Use Put Metric Data to create test data.")
            .contextMenu {
                Button("Put Metric Data") { showPutMetricSheet = true }
                    .disabled(appState.isReadOnly)
            }
        } else {
            VStack(spacing: 0) {
                if metrics.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter metrics")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                List(selection: Binding<CloudWatchMetric.ID?>(
                    get: { activeMetric?.id },
                    set: { newID in
                        activeMetric = metrics.first { $0.id == newID }
                    }
                )) {
                    ForEach(groupedMetrics, id: \.namespace) { group in
                        DisclosureGroup(group.namespace) {
                            ForEach(group.metrics) { metric in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(metric.metricName)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        if !metric.dimensions.isEmpty {
                                            HStack(spacing: 4) {
                                                ForEach(metric.dimensions, id: \.name) { dim in
                                                    StatusBadge(text: "\(dim.name)=\(dim.value)", color: .secondary)
                                                }
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .tag(metric.id)
                                .contextMenu {
                                    Button("Copy Metric Name") { copyToClipboard(metric.metricName) }
                                    Button("Copy Namespace") { copyToClipboard(metric.namespace) }
                                    Menu("Copy as AWS CLI") {
                                        Button("List Metrics (Namespace)") {
                                            copyToClipboard(metric.listMetricsCLI(endpointUrl: appState.endpoint, region: appState.region))
                                        }
                                        Button("List All Metrics") {
                                            copyToClipboard(CloudWatchMetric.listAllMetricsCLI(endpointUrl: appState.endpoint, region: appState.region))
                                        }
                                    }
                                    Divider()
                                    Button("Put Metric Data") { showPutMetricSheet = true }
                                        .disabled(appState.isReadOnly)
                                }
                            }
                        }
                    }
                }
                .contextMenu {
                    Button("Put Metric Data") { showPutMetricSheet = true }
                        .disabled(appState.isReadOnly)
                }

                Divider()
                HStack {
                    Text("\(metrics.count) metric\(metrics.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Data

    private func loadMetrics(force: Bool = false, silent: Bool = false) {
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
                let loaded = try await service.listMetrics()
                let freshMetrics = loaded.sorted {
                    let cmp = $0.namespace.localizedStandardCompare($1.namespace)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return $0.metricName.localizedStandardCompare($1.metricName) == .orderedAscending
                }
                if metrics != freshMetrics {
                    metrics = freshMetrics
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
}
