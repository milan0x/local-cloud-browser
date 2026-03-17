import SwiftUI

struct CloudWatchCreateAlarmView: View {
    @ObservedObject var service: CloudWatchService
    @EnvironmentObject private var licenseManager: LicenseManager
    let existingAlarmNames: Set<String>
    var onCreate: ((String) -> Void)? = nil
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
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
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
                licenseManager.incrementCreateCount(for: .cloudWatch)
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
