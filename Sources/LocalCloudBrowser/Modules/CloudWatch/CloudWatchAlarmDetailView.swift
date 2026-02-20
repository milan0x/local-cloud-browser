import SwiftUI

struct CloudWatchAlarmDetailView: View {
    let alarm: CloudWatchAlarm

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alarm.alarmName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(alarm.thresholdDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    alarmStateBadge(alarm.alarmState)
                }

                Divider()

                // Configuration
                GroupBox("Configuration") {
                    VStack(spacing: 0) {
                        configRow("Namespace", value: alarm.namespace)
                        configRow("Metric Name", value: alarm.metricName)
                        configRow("Statistic", value: alarm.statistic)
                        configRow("Period", value: "\(alarm.period)s")
                        configRow("Evaluation Periods", value: "\(alarm.evaluationPeriods)")
                        configRow("Comparison", value: CloudWatchComparisonOperator(rawValue: alarm.comparisonOperator)?.displayName ?? alarm.comparisonOperator)
                        configRow("Threshold", value: formatThreshold(alarm.threshold))
                    }
                }

                // Dimensions
                if !alarm.dimensions.isEmpty {
                    GroupBox("Dimensions") {
                        VStack(spacing: 0) {
                            ForEach(alarm.dimensions, id: \.name) { dim in
                                configRow(dim.name, value: dim.value)
                            }
                        }
                    }
                }

                // State
                GroupBox("State") {
                    VStack(spacing: 0) {
                        configRow("State", value: alarm.alarmState.displayName)
                        if !alarm.stateReason.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reason")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(alarm.stateReason)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                        }
                        if let updated = alarm.updatedTimestamp {
                            configRow("Updated", value: Self.dateFormatter.string(from: updated))
                        }
                    }
                }

                // Actions
                if !alarm.alarmActions.isEmpty {
                    GroupBox("Alarm Actions") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(alarm.alarmActions, id: \.self) { action in
                                Text(action)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // ARN
                if !alarm.alarmArn.isEmpty {
                    GroupBox("ARN") {
                        Text(alarm.alarmArn)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
            .padding(16)
        }
    }

    private func configRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func alarmStateBadge(_ state: CloudWatchAlarmState) -> some View {
        StatusBadge(text: state.displayName, color: state.color)
    }

    private func formatThreshold(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
