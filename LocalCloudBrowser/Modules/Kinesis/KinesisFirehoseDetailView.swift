import SwiftUI

struct KinesisFirehoseDetailView: View {
    @ObservedObject var service: KinesisFirehoseService
    let deliveryStreamName: String

    @State private var detail: FirehoseDeliveryStreamDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading delivery stream...")
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
                detailContent(detail)
            }
        }
        .task(id: deliveryStreamName) {
            await loadDetail()
        }
    }

    // MARK: - Detail Content

    private func detailContent(_ detail: FirehoseDeliveryStreamDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                streamInfoSection(detail)
                ForEach(Array(detail.destinations.enumerated()), id: \.offset) { index, dest in
                    destinationSection(dest, index: index)
                }
            }
            .padding()
        }
    }

    private func streamInfoSection(_ detail: FirehoseDeliveryStreamDetail) -> some View {
        GroupBox("Stream Info") {
            VStack(spacing: 6) {
                labeledRow("Name", detail.deliveryStreamName)
                labeledRow("ARN", detail.deliveryStreamARN)
                HStack {
                    Text("Status")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    statusBadge(detail.deliveryStreamStatus)
                    Spacer()
                }
                HStack {
                    Text("Type")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    typeBadge(detail.deliveryStreamType)
                    Spacer()
                }
                labeledRow("Version", detail.versionId)
                if let created = detail.createTimestamp {
                    HStack {
                        Text("Created")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(created, style: .date)
                        Text(created, style: .time)
                        Spacer()
                    }
                }
                if let updated = detail.lastUpdateTimestamp {
                    HStack {
                        Text("Last Updated")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(updated, style: .date)
                        Text(updated, style: .time)
                        Spacer()
                    }
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
        }
    }

    private func destinationSection(_ dest: FirehoseDestination, index: Int) -> some View {
        GroupBox("Destination \(index + 1) — \(dest.type)") {
            VStack(spacing: 6) {
                labeledRow("Destination ID", dest.destinationId)
                if let bucket = dest.bucketARN {
                    labeledRow("Bucket ARN", bucket)
                }
                if let prefix = dest.prefix, !prefix.isEmpty {
                    labeledRow("Prefix", prefix)
                }
                if let compression = dest.compressionFormat {
                    labeledRow("Compression", compression)
                }
                if let interval = dest.bufferingIntervalInSeconds {
                    labeledRow("Buffering Interval", "\(interval)s")
                }
                if let size = dest.bufferingSizeInMBs {
                    labeledRow("Buffering Size", "\(size) MB")
                }
                if let role = dest.roleARN {
                    labeledRow("Role ARN", role)
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
        }
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func statusBadge(_ status: String) -> some View {
        StatusBadge(text: status, color: statusColor(status))
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "ACTIVE": .green
        case "CREATING": .orange
        case "DELETING", "DELETING_FAILED": .red
        case "CREATING_FAILED": .red
        default: .gray
        }
    }

    private func typeBadge(_ type: String) -> some View {
        StatusBadge(text: type, color: typeColor(type))
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "KinesisStreamAsSource": .purple
        default: .gray
        }
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            detail = try await service.describeDeliveryStream(name: deliveryStreamName)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
