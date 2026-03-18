import SwiftUI
import Charts

struct CloudWatchMetricChartView: View {
    @ObservedObject var service: CloudWatchService
    let metric: CloudWatchMetric

    @State private var timeRange: CloudWatchTimeRange = .oneHour
    @State private var statistic: CloudWatchStatistic = .average
    @State private var datapoints: [CloudWatchDatapoint] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private static let chartDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading && datapoints.isEmpty {
                ProgressView("Loading datapoints...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, datapoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadData() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if datapoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No datapoints")
                        .foregroundStyle(.secondary)
                    Text("No data for the selected time range and statistic.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        chartView
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        Divider()

                        dataTable
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .task { loadData() }
        .onChange(of: metric) { loadData() }
        .onChange(of: timeRange) { loadData() }
        .onChange(of: statistic) { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.metricName)
                        .font(.headline)
                    Text(metric.namespace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(CloudWatchTimeRange.allCases, id: \.self) { range in
                        Text(range.displayLabel).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Picker("Statistic", selection: $statistic) {
                    ForEach(CloudWatchStatistic.allCases, id: \.self) { stat in
                        Text(stat.rawValue).tag(stat)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Chart

    private var chartView: some View {
        let values = datapoints.compactMap { dp -> (date: Date, value: Double)? in
            guard let v = dp.value(for: statistic) else { return nil }
            return (dp.timestamp, v)
        }

        return Chart(values, id: \.date) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(statistic.rawValue, point.value)
            )
            .foregroundStyle(.blue)

            PointMark(
                x: .value("Time", point.date),
                y: .value(statistic.rawValue, point.value)
            )
            .foregroundStyle(.blue)
            .symbolSize(20)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 220)
    }

    // MARK: - Data Table

    private var dataTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Timestamp")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 180, alignment: .leading)
                Text(statistic.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 120, alignment: .trailing)
                Text("Unit")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 100, alignment: .trailing)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.08))

            ForEach(datapoints) { dp in
                HStack {
                    Text(Self.dateFormatter.string(from: dp.timestamp))
                        .font(.caption)
                        .frame(width: 180, alignment: .leading)
                    if let val = dp.value(for: statistic) {
                        Text(formatValue(val))
                            .font(.caption.monospacedDigit())
                            .frame(width: 120, alignment: .trailing)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                    Text(dp.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Spacer()
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                Divider()
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let endTime = Date()
                let startTime = endTime.addingTimeInterval(-Double(timeRange.seconds))
                let loaded = try await service.getMetricStatistics(
                    metric: metric,
                    startTime: startTime,
                    endTime: endTime,
                    period: timeRange.suggestedPeriod,
                    statistics: [statistic]
                )
                datapoints = loaded
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
    }
}
