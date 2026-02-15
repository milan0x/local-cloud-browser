import SwiftUI

struct CloudWatchSetAlarmStateView: View {
    @ObservedObject var service: CloudWatchService
    let alarm: CloudWatchAlarm
    @Environment(\.dismiss) private var dismiss

    @State private var selectedState: CloudWatchAlarmState = .ok
    @State private var reason = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private var isValid: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Alarm") {
                        Text(alarm.alarmName)
                    }
                    LabeledContent("Current State") {
                        Text(alarm.alarmState.displayName)
                    }
                }

                Section("New State") {
                    Picker("State", selection: $selectedState) {
                        Text("OK").tag(CloudWatchAlarmState.ok)
                        Text("ALARM").tag(CloudWatchAlarmState.alarm)
                        Text("INSUFFICIENT DATA").tag(CloudWatchAlarmState.insufficientData)
                    }
                    TextField("Reason", text: $reason)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set State") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.setAlarmState(
                    name: alarm.alarmName,
                    state: selectedState,
                    reason: reason.trimmingCharacters(in: .whitespaces)
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
