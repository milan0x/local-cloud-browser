import SwiftUI
import AppKit

struct CloudWatchLogsEventListView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroupName: String
    let logStreamName: String

    @State private var events: [CloudWatchLogEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var nextForwardToken: String?
    @State private var isLoadingMore = false

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && events.isEmpty {
                ProgressView("Loading events...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, events.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadEvents() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                EmptyStateView(icon: "text.page", message: "No events")
            } else {
                List(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        if let ts = event.timestamp {
                            Text(Self.timestampFormatter.string(from: ts))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.displayMessage)
                            .font(.body.monospaced())
                            .lineLimit(nil)
                            .textSelection(.enabled)
                    }
                    .contextMenu {
                        Button("Copy Message") {
                            copyToClipboard(event.message)
                        }
                        if event.isJSON, let pretty = event.prettyPrinted {
                            Button("Copy Pretty-Printed") {
                                copyToClipboard(pretty)
                            }
                        }
                    }
                }

                // Status bar
                Divider()
                HStack {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if nextForwardToken != nil {
                        Button {
                            loadMore()
                        } label: {
                            if isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Load More")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLoadingMore)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .task { loadEvents() }
    }

    // MARK: - Data

    private func loadEvents() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.getLogEvents(
                    logGroupName: logGroupName,
                    logStreamName: logStreamName,
                    startFromHead: true
                )
                events = result.events
                nextForwardToken = result.nextForwardToken
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadMore() {
        guard let token = nextForwardToken, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            do {
                let result = try await service.getLogEvents(
                    logGroupName: logGroupName,
                    logStreamName: logStreamName,
                    startFromHead: true,
                    nextToken: token
                )
                if !result.events.isEmpty {
                    events.append(contentsOf: result.events)
                }
                // CloudWatch returns the same token if no more events
                if result.nextForwardToken != token {
                    nextForwardToken = result.nextForwardToken
                } else {
                    nextForwardToken = nil
                }
            } catch {
                // silently fail on load more
            }
            isLoadingMore = false
        }
    }
}
