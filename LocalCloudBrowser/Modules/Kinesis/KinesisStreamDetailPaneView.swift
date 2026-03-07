import SwiftUI

struct KinesisStreamDetailPaneView: View {
    @ObservedObject var service: KinesisService
    let streamName: String

    @State private var detail: KinesisStreamDetail?
    @State private var shards: [KinesisShard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedShardID: String?
    @State private var records: [KinesisRecord] = []
    @State private var isLoadingRecords = false
    @State private var recordsError: String?
    @State private var nextShardIterator: String?

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading stream...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, detail == nil {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadDetail() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                streamContent(detail)
            }
        }
        .task(id: streamName) {
            await loadDetail()
        }
    }

    // MARK: - Stream Content

    private func streamContent(_ detail: KinesisStreamDetail) -> some View {
        VStack(spacing: 0) {
            summaryHeader(detail)
            Divider()
            HSplitView {
                shardList
                    .frame(width: 220)
                recordsPane
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Summary Header

    private func summaryHeader(_ detail: KinesisStreamDetail) -> some View {
        HStack(spacing: 10) {
            statusBadge(detail.streamStatus)
            modeBadge(detail.streamMode)

            HStack(spacing: 4) {
                Text("Retention:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(detail.retentionPeriodHours)h")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Text("Shards:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(detail.openShardCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            if detail.encryptionType != "NONE" {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text(detail.encryptionType)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    private func statusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: statusColor(status))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ACTIVE": .green
        case "CREATING": .orange
        case "DELETING": .red
        case "UPDATING": .blue
        default: .gray
        }
    }

    private func modeBadge(_ mode: String) -> some View {
        StatusBadge(text: mode, color: modeColor(mode))
    }

    private func modeColor(_ mode: String) -> Color {
        switch mode {
        case "ON_DEMAND": .purple
        default: .gray
        }
    }

    // MARK: - Shard List

    private var shardList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shards")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if shards.isEmpty {
                Text("No shards")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedShardID) {
                    ForEach(shards) { shard in
                        shardRow(shard)
                            .tag(shard.id)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: selectedShardID) {
            if let shardId = selectedShardID {
                loadRecords(shardId: shardId)
            } else {
                records = []
                nextShardIterator = nil
            }
        }
    }

    private func shardRow(_ shard: KinesisShard) -> some View {
        HStack(spacing: 6) {
            Text(shard.truncatedId)
                .font(.caption)
                .monospaced()
                .lineLimit(1)

            Spacer()

            StatusBadge(text: shard.isClosed ? "Closed" : "Open", color: shard.isClosed ? .secondary : .green)
        }
    }

    // MARK: - Records Pane

    private var recordsPane: some View {
        VStack(spacing: 0) {
            if selectedShardID == nil {
                EmptyDetailView(icon: "doc.text.magnifyingglass", message: "Select a shard to view records")
            } else if isLoadingRecords && records.isEmpty {
                ProgressView("Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = recordsError, records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No records in this shard")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                recordsList
            }
        }
    }

    private var recordsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(records.count) record\(records.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingRecords {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                }
                .padding(.vertical, 4)

                if nextShardIterator != nil {
                    Button("Load More") {
                        loadMoreRecords()
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Record Row

    private func recordRow(_ record: KinesisRecord) -> some View {
        DisclosureGroup {
            recordDetail(record)
                .padding(.leading, 4)
                .padding(.vertical, 4)
        } label: {
            HStack(spacing: 8) {
                Text(record.partitionKey)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if let date = record.approximateArrivalTimestamp {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func recordDetail(_ record: KinesisRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Partition Key:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(record.partitionKey)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Text("Seq:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(record.sequenceNumber)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Data")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ScrollView([.horizontal, .vertical]) {
                    Text(record.prettyJSON ?? record.decodedData)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 200)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        selectedShardID = nil
        records = []
        nextShardIterator = nil
        do {
            async let detailResult = service.describeStreamSummary(name: streamName)
            async let shardsResult = service.listShards(name: streamName)
            let (loadedDetail, loadedShards) = try await (detailResult, shardsResult)
            detail = loadedDetail
            shards = loadedShards
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadRecords(shardId: String) {
        records = []
        nextShardIterator = nil
        recordsError = nil
        isLoadingRecords = true
        Task {
            do {
                let iterator = try await service.getShardIterator(
                    name: streamName,
                    shardId: shardId
                )
                let (fetchedRecords, nextIter) = try await service.getRecords(iterator: iterator)
                if selectedShardID == shardId {
                    records = fetchedRecords
                    nextShardIterator = nextIter
                }
            } catch {
                if selectedShardID == shardId {
                    recordsError = error.localizedDescription
                }
            }
            isLoadingRecords = false
        }
    }

    private func loadMoreRecords() {
        guard let iterator = nextShardIterator else { return }
        isLoadingRecords = true
        Task {
            do {
                let (fetchedRecords, nextIter) = try await service.getRecords(iterator: iterator)
                records.append(contentsOf: fetchedRecords)
                nextShardIterator = nextIter
            } catch {
                // Iterator may have expired — re-fetch
                if let shardId = selectedShardID {
                    do {
                        let newIterator = try await service.getShardIterator(
                            name: streamName,
                            shardId: shardId,
                            type: "TRIM_HORIZON"
                        )
                        let (fetchedRecords, nextIter) = try await service.getRecords(iterator: newIterator)
                        records = fetchedRecords
                        nextShardIterator = nextIter
                    } catch {
                        recordsError = error.localizedDescription
                    }
                }
            }
            isLoadingRecords = false
        }
    }
}
