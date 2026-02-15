import SwiftUI

struct DynamoDBStreamBrowserView: View {
    @ObservedObject var service: DynamoDBService
    let table: DynamoDBTable
    let tableDetail: DynamoDBTableDetail

    @State private var streamDescription: DynamoDBStreamDescription?
    @State private var isLoadingStream = false
    @State private var streamError: String?

    @State private var selectedShardID: String?
    @State private var records: [DynamoDBStreamRecord] = []
    @State private var isLoadingRecords = false
    @State private var recordsError: String?
    @State private var nextShardIterator: String?

    var body: some View {
        Group {
            if !tableDetail.streamEnabled {
                noStreamPlaceholder
            } else if isLoadingStream && streamDescription == nil {
                ProgressView("Loading stream...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = streamError, streamDescription == nil {
                errorPlaceholder(error)
            } else if let desc = streamDescription {
                streamContent(desc)
            }
        }
        .task(id: tableDetail.latestStreamArn) {
            if tableDetail.streamEnabled, let arn = tableDetail.latestStreamArn {
                await loadStream(arn: arn)
            }
        }
    }

    // MARK: - Placeholders

    private var noStreamPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Streams not enabled")
                .foregroundStyle(.secondary)
            Text("Enable DynamoDB Streams on this table to view stream records.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry") {
                if let arn = tableDetail.latestStreamArn {
                    Task { await loadStream(arn: arn) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stream Content

    private func streamContent(_ desc: DynamoDBStreamDescription) -> some View {
        VStack(spacing: 0) {
            streamInfoHeader(desc)
            Divider()
            HSplitView {
                shardList(desc.shards)
                    .frame(width: 220)
                recordsPane
                    .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Stream Info Header

    private func streamInfoHeader(_ desc: DynamoDBStreamDescription) -> some View {
        HStack(spacing: 10) {
            StatusBadge(text: desc.streamStatus, color: desc.streamStatus == "ENABLED" ? .green : .orange)

            StatusBadge(text: desc.streamViewType, color: .blue)

            CopyableValue(text: desc.streamLabel)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(desc.shards.count) shard\(desc.shards.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Shard List

    private func shardList(_ shards: [DynamoDBShard]) -> some View {
        VStack(spacing: 0) {
            shardListHeader
            Divider()
            shardListContent(shards)
        }
        .onChange(of: selectedShardID) {
            if let shardId = selectedShardID,
               let arn = tableDetail.latestStreamArn {
                loadRecords(streamArn: arn, shardId: shardId)
            } else {
                records = []
                nextShardIterator = nil
            }
        }
    }

    private var shardListHeader: some View {
        HStack {
            Text("Shards")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func shardListContent(_ shards: [DynamoDBShard]) -> some View {
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

    private func shardRow(_ shard: DynamoDBShard) -> some View {
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
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Select a shard to view records")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func recordRow(_ record: DynamoDBStreamRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup {
                recordDetail(record)
                    .padding(.leading, 4)
                    .padding(.vertical, 4)
            } label: {
                HStack(spacing: 8) {
                    StatusBadge(text: record.eventName, color: record.eventColor)

                    Text(record.keySummary)
                        .font(.caption)
                        .monospaced()
                        .lineLimit(1)

                    Spacer()

                    if let date = record.approximateCreationDateTime {
                        Text(date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Text("\(record.sizeBytes) B")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func recordDetail(_ record: DynamoDBStreamRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !record.keys.isEmpty {
                imageSection(title: "Keys", attributes: record.keys)
            }
            if let newImage = record.newImage, !newImage.isEmpty {
                imageSection(title: "New Image", attributes: newImage)
            }
            if let oldImage = record.oldImage, !oldImage.isEmpty {
                imageSection(title: "Old Image", attributes: oldImage)
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Seq:")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(record.sequenceNumber)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func imageSection(title: String, attributes: [String: AttributeValue]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(spacing: 6) {
                        Text(key)
                            .font(.caption)
                            .fontWeight(.medium)

                        StatusBadge(text: value.typeBadge, color: Color.accentColor)

                        Text(value.displayString)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Loading

    private func loadStream(arn: String) async {
        isLoadingStream = true
        streamError = nil
        selectedShardID = nil
        records = []
        nextShardIterator = nil
        do {
            streamDescription = try await service.describeStream(streamArn: arn)
        } catch {
            streamError = error.localizedDescription
        }
        isLoadingStream = false
    }

    private func loadRecords(streamArn: String, shardId: String) {
        records = []
        nextShardIterator = nil
        recordsError = nil
        isLoadingRecords = true
        Task {
            do {
                let iterator = try await service.getShardIterator(
                    streamArn: streamArn,
                    shardId: shardId
                )
                let (fetchedRecords, nextIter) = try await service.getRecords(shardIterator: iterator)
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
                let (fetchedRecords, nextIter) = try await service.getRecords(shardIterator: iterator)
                records.append(contentsOf: fetchedRecords)
                nextShardIterator = nextIter
            } catch {
                // Iterator may have expired — re-fetch if we have the context
                if let shardId = selectedShardID,
                   let arn = tableDetail.latestStreamArn {
                    do {
                        let newIterator = try await service.getShardIterator(
                            streamArn: arn,
                            shardId: shardId,
                            type: "TRIM_HORIZON"
                        )
                        let (fetchedRecords, nextIter) = try await service.getRecords(shardIterator: newIterator)
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
