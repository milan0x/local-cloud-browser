import SwiftUI

struct StepFunctionsExecutionHistoryView: View {
    @ObservedObject var service: StepFunctionsService
    let executionArn: String

    @State private var events: [StepFunctionsHistoryEvent] = []
    @State private var nextToken: String?
    @State private var isLoading = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Execution History")
                .font(.headline)

            if isLoading && events.isEmpty {
                ProgressView("Loading history...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if events.isEmpty {
                Text("No history events")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 8) {
                        Text("#\(event.id)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)

                        eventTypeBadge(event.type, color: event.badgeColor)

                        Spacer()

                        if let ts = event.timestamp {
                            Text(ts.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Status bar + Load More
                HStack {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if nextToken != nil {
                        Button("Load More") {
                            loadMore()
                        }
                        .font(.caption)
                        .disabled(isLoading)
                    }
                }
                .padding(.top, 4)
            }
        }
        .serviceErrorAlert(error: $serviceError)
        .task { loadHistory() }
        .onChange(of: executionArn) {
            events = []
            nextToken = nil
            loadHistory()
        }
    }

    private func eventTypeBadge(_ type: String, color: String) -> some View {
        StatusBadge(text: type, color: badgeColor(color))
            .lineLimit(1)
    }

    private func badgeColor(_ name: String) -> Color {
        switch name {
        case "green": .green
        case "red": .red
        case "cyan": .cyan
        case "blue": .blue
        case "orange": .orange
        case "purple": .purple
        case "indigo": .indigo
        default: .gray
        }
    }

    private func loadHistory() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let result = try await service.getExecutionHistory(arn: executionArn)
                events = result.events
                nextToken = result.nextToken
            } catch {
                serviceError = error.asServiceError
            }
            isLoading = false
        }
    }

    private func loadMore() {
        guard !isLoading, let token = nextToken else { return }
        isLoading = true
        Task {
            do {
                let result = try await service.getExecutionHistory(arn: executionArn, nextToken: token)
                events.append(contentsOf: result.events)
                nextToken = result.nextToken
            } catch {
                serviceError = error.asServiceError
            }
            isLoading = false
        }
    }
}
