import SwiftUI

struct EventBridgeCreateScheduleView: View {
    @ObservedObject var service: EventBridgeSchedulerService
    let groupName: String
    var existingScheduleNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var scheduleName = ""
    @State private var scheduleDescription = ""
    @State private var expressionType: ExpressionType = .rate
    @State private var rateValue = "5"
    @State private var rateUnit = "minutes"
    @State private var cronExpression = "0 9 * * ? *"
    @State private var atDateTime = ""
    @State private var timezone = "UTC"
    @State private var targetArn = ""
    @State private var targetRoleArn = ""
    @State private var targetInput = ""
    @State private var isEnabled = true
    @State private var flexMode: FlexMode = .off
    @State private var flexMinutes = "15"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private static let namePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_.\\-]+$")

    enum ExpressionType: String, CaseIterable {
        case rate = "Rate"
        case cron = "Cron"
        case oneTime = "One-Time"
    }

    enum FlexMode: String, CaseIterable {
        case off = "Off"
        case flexible = "Flexible"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Schedule") {
                    TextField("Schedule name", text: $scheduleName)

                    TextField("Description (optional)", text: $scheduleDescription)

                    LabeledContent("Group") {
                        Text(groupName)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Expression type", selection: $expressionType) {
                        ForEach(ExpressionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    expressionInput

                    if let preview = expressionPreview {
                        LabeledContent("Preview") {
                            Text(preview)
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }

                    TextField("Timezone", text: $timezone, prompt: Text("UTC"))

                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section("Target") {
                    TextField("Target ARN", text: $targetArn, prompt: Text("arn:aws:lambda:us-east-1:000000000000:function:my-func"))

                    TextField("Role ARN", text: $targetRoleArn, prompt: Text("arn:aws:iam::000000000000:role/scheduler-role"))

                    TextField("Input JSON (optional)", text: $targetInput, prompt: Text("{\"key\": \"value\"}"))
                }

                Section("Flexible Time Window") {
                    Picker("Mode", selection: $flexMode) {
                        ForEach(FlexMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    if flexMode == .flexible {
                        TextField("Maximum window (minutes)", text: $flexMinutes)
                    }
                }
            }
            .formStyle(.grouped)

            validationMessages

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving || appState.isReadOnly)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 580)
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Expression Input

    @ViewBuilder
    private var expressionInput: some View {
        switch expressionType {
        case .rate:
            HStack {
                TextField("Value", text: $rateValue)
                    .frame(width: 60)
                Picker("Unit", selection: $rateUnit) {
                    Text("minutes").tag("minutes")
                    Text("hours").tag("hours")
                    Text("days").tag("days")
                }
            }
        case .cron:
            TextField("Cron expression", text: $cronExpression, prompt: Text("0 9 * * ? *"))
                .font(.system(.body, design: .monospaced))
        case .oneTime:
            TextField("Date/time", text: $atDateTime, prompt: Text("2025-01-01T00:00:00"))
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Validation

    @ViewBuilder
    private var validationMessages: some View {
        if nameExists {
            validationLabel("A schedule named \"\(trimmedName)\" already exists in this group.")
        } else if !trimmedName.isEmpty && !nameMatchesPattern {
            validationLabel("Name must contain only letters, numbers, periods, hyphens, and underscores.")
        } else if !trimmedName.isEmpty && trimmedName.count > 64 {
            validationLabel("Name must be 64 characters or fewer.")
        }
    }

    private func validationLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.red)
            .font(.caption)
            .padding(.horizontal)
    }

    private var trimmedName: String {
        scheduleName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingScheduleNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var builtExpression: String {
        switch expressionType {
        case .rate:
            return "rate(\(rateValue) \(rateUnit))"
        case .cron:
            return "cron(\(cronExpression))"
        case .oneTime:
            return "at(\(atDateTime))"
        }
    }

    private var expressionPreview: String? {
        ScheduleExpressionHelper.humanReadable(builtExpression)
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty && !nameExists && nameMatchesPattern && trimmedName.count <= 64 else {
            return false
        }
        guard !targetArn.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !targetRoleArn.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        switch expressionType {
        case .rate:
            guard let val = Int(rateValue), val > 0 else { return false }
        case .cron:
            guard !cronExpression.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        case .oneTime:
            guard !atDateTime.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }

        if flexMode == .flexible {
            guard let mins = Int(flexMinutes), mins > 0 else { return false }
        }

        return true
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let flexModeStr = flexMode == .flexible ? "FLEXIBLE" : "OFF"
                let flexMins = flexMode == .flexible ? Int(flexMinutes) : nil
                let input = targetInput.trimmingCharacters(in: .whitespacesAndNewlines)

                try await service.createSchedule(
                    name: trimmedName,
                    groupName: groupName,
                    expression: builtExpression,
                    timezone: timezone.trimmingCharacters(in: .whitespaces),
                    description: scheduleDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    state: isEnabled ? "ENABLED" : "DISABLED",
                    targetArn: targetArn.trimmingCharacters(in: .whitespaces),
                    targetRoleArn: targetRoleArn.trimmingCharacters(in: .whitespaces),
                    targetInput: input.isEmpty ? nil : input,
                    flexibleTimeWindowMode: flexModeStr,
                    flexibleTimeWindowMaxMinutes: flexMins
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
