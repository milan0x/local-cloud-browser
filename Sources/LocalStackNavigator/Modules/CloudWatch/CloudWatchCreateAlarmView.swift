import SwiftUI

struct CloudWatchCreateAlarmView: View {
    @ObservedObject var service: CloudWatchService
    let existingAlarmNames: Set<String>
    @Environment(\.dismiss) private var dismiss

    @State private var alarmName = ""
    @State private var namespace = ""
    @State private var metricName = ""
    @State private var statistic: CloudWatchStatistic = .average
    @State private var period = "300"
    @State private var evaluationPeriods = "1"
    @State private var comparisonOperator: CloudWatchComparisonOperator = .greaterThanThreshold
    @State private var threshold = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private var trimmedName: String {
        alarmName.trimmingCharacters(in: .whitespaces)
    }

    private var nameCollision: Bool {
        existingAlarmNames.contains(trimmedName)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty &&
        !nameCollision &&
        !namespace.trimmingCharacters(in: .whitespaces).isEmpty &&
        !metricName.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(period) != nil && (Int(period) ?? 0) > 0 &&
        Int(evaluationPeriods) != nil && (Int(evaluationPeriods) ?? 0) > 0 &&
        Double(threshold) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Alarm Name", text: $alarmName)
                    if nameCollision {
                        Text("An alarm with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Metric") {
                    TextField("Namespace", text: $namespace)
                    TextField("Metric Name", text: $metricName)

                    Picker("Statistic", selection: $statistic) {
                        ForEach(CloudWatchStatistic.allCases, id: \.self) { stat in
                            Text(stat.rawValue).tag(stat)
                        }
                    }
                }

                Section("Conditions") {
                    TextField("Period (seconds)", text: $period)
                    TextField("Evaluation Periods", text: $evaluationPeriods)

                    Picker("Comparison", selection: $comparisonOperator) {
                        ForEach(CloudWatchComparisonOperator.allCases, id: \.self) { op in
                            Text("\(op.displayName) (\(op.rawValue))").tag(op)
                        }
                    }

                    TextField("Threshold", text: $threshold)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 450)
        .serviceErrorAlert(error: $serviceError)
    }

    private func save() {
        guard let periodInt = Int(period),
              let evalPeriods = Int(evaluationPeriods),
              let thresholdVal = Double(threshold) else { return }

        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.putMetricAlarm(
                    name: trimmedName,
                    namespace: namespace.trimmingCharacters(in: .whitespaces),
                    metricName: metricName.trimmingCharacters(in: .whitespaces),
                    statistic: statistic.rawValue,
                    period: periodInt,
                    evaluationPeriods: evalPeriods,
                    comparisonOperator: comparisonOperator.rawValue,
                    threshold: thresholdVal
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
