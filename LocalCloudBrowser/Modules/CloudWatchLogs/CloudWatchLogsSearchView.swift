import SwiftUI
import AppKit

struct CloudWatchLogsSearchView: View {
    @ObservedObject var service: CloudWatchLogsService
    let logGroup: CloudWatchLogGroup
    @Environment(\.dismiss) private var dismiss

    @State private var filterPattern = ""
    @State private var useTimeRange = false
    @State private var startTime = Date().addingTimeInterval(-3600)
    @State private var endTime = Date()
    @State private var results: [CloudWatchFilteredLogEvent] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var nextToken: String?
    @State private var isLoadingMore = false
    @State private var serviceError: ServiceError?

    private var hasInvalidDateRange: Bool {
        useTimeRange && startTime >= endTime
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Filter") {
                    TextField("Filter pattern (e.g. ERROR, { $.level = \"error\" })", text: $filterPattern)
                }

                Section("Time Range") {
                    Toggle("Limit time range", isOn: $useTimeRange)
                    if useTimeRange {
                        DatePicker("From", selection: $startTime)
                        DatePicker("To", selection: $endTime)
                        if hasInvalidDateRange {
                            Text("\"From\" must be earlier than \"To\"")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button {
                        search()
                    } label: {
                        HStack {
                            Spacer()
                            if isSearching {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching...")
                            } else {
                                Text("Search")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSearching || hasInvalidDateRange)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)

            Divider()

            // Results
            if hasSearched {
                if results.isEmpty && !isSearching {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("No matching events")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                StatusBadge(text: event.logStreamName, color: .purple)
                                if let ts = event.timestamp {
                                    Text(Self.timestampFormatter.string(from: ts))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Enter a filter pattern and search")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Status bar
            Divider()
            HStack {
                if hasSearched {
                    Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if nextToken != nil {
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
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 700)
        .frame(minHeight: 600)
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Search

    private func search() {
        isSearching = true
        results = []
        nextToken = nil
        hasSearched = true
        Task {
            do {
                let result = try await service.filterLogEvents(
                    logGroupName: logGroup.logGroupName,
                    filterPattern: filterPattern.isEmpty ? nil : filterPattern,
                    startTime: useTimeRange ? startTime : nil,
                    endTime: useTimeRange ? endTime : nil
                )
                results = result.events
                nextToken = result.nextToken
            } catch {
                serviceError = error.asServiceError
            }
            isSearching = false
        }
    }

    private func loadMore() {
        guard let token = nextToken, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            do {
                let result = try await service.filterLogEvents(
                    logGroupName: logGroup.logGroupName,
                    filterPattern: filterPattern.isEmpty ? nil : filterPattern,
                    startTime: useTimeRange ? startTime : nil,
                    endTime: useTimeRange ? endTime : nil,
                    nextToken: token
                )
                results.append(contentsOf: result.events)
                nextToken = result.nextToken
            } catch {
                serviceError = error.asServiceError
            }
            isLoadingMore = false
        }
    }
}
