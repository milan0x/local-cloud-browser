import SwiftUI
import AppKit

struct Route53RecordSetBrowserView: View {
    @ObservedObject var service: Route53Service
    let zone: Route53HostedZone
    @ObservedObject var toolbarState: Route53ToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var recordSets: [Route53RecordSet] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateRecordSheet = false
    @State private var recordToDelete: Route53RecordSet?
    @State private var serviceError: ServiceError?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            zoneHeader
            Divider()
            recordSetContent
        }
        .sheet(isPresented: $showCreateRecordSheet) {
            Route53CreateRecordView(service: service, zoneId: zone.id, zoneName: zone.name)
                .onDisappear { loadRecords(force: true) }
        }
        .alert(
            "Delete Record",
            isPresented: Binding(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let record = recordToDelete {
                    deleteRecord(record)
                }
            }
            Button("Cancel", role: .cancel) {
                recordToDelete = nil
            }
        } message: {
            if let record = recordToDelete {
                Text("Are you sure you want to delete the \(record.type) record for \"\(record.displayName)\"?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task(id: zone.id) { loadRecords() }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateRecordSheet && recordToDelete == nil && !isLoading else { return }
            loadRecords(force: true, silent: true)
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .createRecord:
                toolbarState.pendingAction = nil
                showCreateRecordSheet = true
            case .createZone, .deleteZone:
                break // handled by zone list
            }
        }
    }

    // MARK: - Zone Header

    private var zoneHeader: some View {
        HStack(spacing: 10) {
            Text(zone.displayName)
                .font(.headline)
                .lineLimit(1)

            CopyableValue(text: zone.id)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)

            if zone.privateZone {
                Text("Private")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            } else {
                Text("Public")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }

            Spacer()

            Text("\(recordSets.count) record\(recordSets.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Content

    private var filteredRecords: [Route53RecordSet] {
        guard !searchText.isEmpty else { return recordSets }
        let query = searchText.lowercased()
        return recordSets.filter {
            $0.name.lowercased().contains(query) ||
            $0.type.lowercased().contains(query) ||
            $0.valuesPreview.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var recordSetContent: some View {
        if isLoading && recordSets.isEmpty {
            ProgressView("Loading records...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, recordSets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                Button("Retry") { loadRecords(force: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if recordSets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No record sets")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if recordSets.count > 5 {
                    SearchBarView(query: $searchText, placeholder: "Filter records")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    Divider()
                }
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredRecords) { record in
                            recordRow(record)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Record Row

    private func recordRow(_ record: Route53RecordSet) -> some View {
        DisclosureGroup {
            recordDetail(record)
                .padding(.leading, 4)
                .padding(.vertical, 4)
        } label: {
            HStack(spacing: 8) {
                Text(record.type)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(record.typeBadgeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(record.typeBadgeColor)
                    .frame(width: 52)

                Text(record.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if let ttl = record.ttl {
                    Text("\(ttl)s")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if record.isAlias {
                    Text("ALIAS")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Name") { copyToClipboard(record.name) }
            Button("Copy Values") { copyToClipboard(record.valuesPreview) }
            Divider()
            if !record.isAlias && record.type != "SOA" && record.type != "NS" {
                Button("Delete", role: .destructive) {
                    recordToDelete = record
                }
                .disabled(appState.isReadOnly)
            }
        }
    }

    private func recordDetail(_ record: Route53RecordSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let alias = record.aliasTarget {
                labeledRow("Alias Target") {
                    Text(alias.dnsName)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                labeledRow("Alias Zone") {
                    Text(alias.hostedZoneId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                labeledRow("Values") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(record.values, id: \.self) { value in
                            Text(value)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let ttl = record.ttl {
                labeledRow("TTL") {
                    Text("\(ttl) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let weight = record.weight {
                labeledRow("Weight") {
                    Text("\(weight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let setId = record.setIdentifier {
                labeledRow("Set ID") {
                    Text(setId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadRecords(force: Bool = false, silent: Bool = false) {
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await service.listResourceRecordSets(zoneId: zone.id)
                if recordSets != loaded {
                    recordSets = loaded
                }
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
            }
        }
    }

    private func deleteRecord(_ record: Route53RecordSet) {
        Task {
            do {
                try await service.deleteRecordSet(zoneId: zone.id, recordSet: record)
                loadRecords(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
